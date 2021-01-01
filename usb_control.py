#!/usr/bin/env python3
import sys
import signal
import os
import subprocess
import tkinter as tk
from tkinter import ttk
import tkinter.font as tkfont
import collections

__author__ = "Steve Magnuson AG7GN"
__copyright__ = "Copyright 2020, Steve Magnuson"
__credits__ = ["Steve Magnuson"]
__license__ = "GPL"
__version__ = "1.0.3"
__maintainer__ = "Steve Magnuson"
__email__ = "ag7gn@arrl.net"
__status__ = "Production"


class UsbWindow(object):
    """
    GUI that allows user to click on a USB device to toggle it's state
    between 'bound' (enabled) or 'unbound' (disabled).
    """
    treeview_font = (None, 12,)
    treeview_header_font = (None, 12, 'bold')
    label_font = (None, 11, 'bold')
    button_font = (None, 12, 'bold')
    max_label_width = 350
    window_padding = 35
    min_window_width = max_label_width + window_padding
    max_window_height = 380

    def __init__(self, master):
        self.master = master
        master.title(f"USB Device Manager - version {__version__}")
        ws = master.winfo_screenwidth()
        hs = master.winfo_screenheight()
        pos_x = (ws // 2) - (self.min_window_width // 2)
        pos_y = (hs // 2) - (self.max_window_height // 2)
        master.geometry(f"+{pos_x}+{pos_y}")
        # master.config(bg="skyblue")
        # Make the label frame & label
        self.header = ["ID", "Tag", "Device", "State"]
        self.label_frame = tk.Frame(master=master, borderwidth=5)
        self.label_frame.pack(side='top', fill='both', padx=5, pady=5, expand=True)
        s = """Click on a device to toggle state.
Empty list means no devices found.
(Enabled = bound, Disabled = unbound)"""
        msg = tk.Label(master=self.label_frame,
                       wraplength=self.max_label_width,
                       justify="center",
                       font=self.label_font, fg='blue',
                       anchor="center", text=s)
        msg.pack(side='top', padx=5, pady=5)
        self.list_frame = tk.Frame(master=master, borderwidth=5)
        self.list_frame.pack(side='top', fill='both', padx=5, pady=5,
                             expand=True)
        style = ttk.Style()
        # Set table header font. 'None' means use the default font.
        style.configure("Treeview.Heading", font=self.treeview_header_font)
        # Set table contents font.
        style.configure("Treeview", font=self.treeview_font)
        self.tree = ttk.Treeview(master=self.list_frame,
                                 columns=self.header,
                                 show="headings", style="Treeview")
        self.tree.bind('<ButtonRelease-1>', self._select_item)
        # NOTE: tags are broken in tkinter 8.6.9!
        self.tree.tag_configure('odd', background='#E8E8E8')
        self.tree.tag_configure('even', background='#DFDFDF')
        vsb = tk.Scrollbar(master=self.list_frame,
                           orient="vertical",
                           command=self.tree.yview)
        # hsb = tk.Scrollbar(master=self.list_frame,
        #                    orient="horizontal",
        #                    command=self.tree.xview)
        # self.tree.configure(yscrollcommand=vsb.set,
        #                     xscrollcommand=hsb.set)
        self.tree.configure(yscrollcommand=vsb.set)
        self.tree.grid(column=0, row=0,
                       sticky='nsew', in_=self.list_frame)
        vsb.grid(column=1, row=0, sticky='ns', in_=self.list_frame)
        # hsb.grid(column=0, row=1, sticky='ew', in_=self.list_frame)
        self.list_frame.grid_columnconfigure(0, weight=1)
        self.list_frame.grid_rowconfigure(0, weight=1)

        self.button_frame = tk.Frame(master=master, borderwidth=5)
        self.button_frame.pack(side='top', fill='both', padx=5, pady=5,
                               expand=True)
        # self.refresh_button = tk.Button(master=self.button_frame,
        #                                 text='Refresh List',
        #                                 command=lambda: self._build_tree())
        # self.refresh_button.pack(padx=5, pady=5, side='left',
        #                          fill='both', expand=True)
        self.quit_button = tk.Button(master=self.button_frame,
                                     text='Quit',
                                     font=self.button_font,
                                     command=lambda:
                                     self.master.quit())
        self.quit_button.pack(side='left',
                              fill='both', expand=True)
        self.current_list = None
        self._update_tree()

    def _build_headers(self):
        """
        Constructs the Treeview table headers and auto-adjusts the
        width of each header using the number of characters in the
        column heading.

        :return: None
        """
        for col in self.header:
            self.tree.heading(col, text=col.title(),
                              command=lambda c=col: self._sort_by(c, 0))
            # Adjust the column's width to the header string
            _width = tkfont.Font(font=self.treeview_header_font).measure(col.title() + '__')
            self.tree.column(col, width=_width)

    def _build_tree(self):
        """
        Calls get_usb_devices and inserts results into the tree. Column
        width auto-adjusts based on the character count in the row
        field with the greatest number of characters.

        :return: None
        """
        self.tree.delete(*self.tree.get_children())
        i = 0
        tree_width = 0
        for item in self.current_list:
            if i % 2 == 0:
                self.tree.insert('', 'end', values=item, tags=('even',))
            else:
                self.tree.insert('', 'end', values=item, tags=('odd',))
            i += 1
            # adjust column's width if necessary to fit each value
            # Use the column's header string as a minimum width
            tree_width = 0
            for ix, val in enumerate(item):
                min_col_w = self.tree.column(self.header[ix], width=None)
                col_w = tkfont.Font(font=self.treeview_font).measure(val + '__')
                if min_col_w < col_w:
                    self.tree.column(self.header[ix], width=col_w)
                    tree_width += col_w
                else:
                    tree_width += min_col_w
        # Update root window width to accommodate the new tree width
        self.master.update_idletasks()
        self.master.update()
        x = self.master.winfo_width()
        y = self.master.winfo_height()
        window_width = max([tree_width + self.window_padding,
                            self.min_window_width])
        if x != window_width:
            self.master.geometry(f"{window_width}x{y}")

    def _select_item(self, _):
        selected = self.tree.focus()
        if not selected:
            return
        _device = self.tree.item(selected)['values'][2]
        _state = self.tree.item(selected)['values'][3].casefold()
        if _state == "enabled":
            target_state = "unbind"
        else:
            target_state = "bind"
        set_usb_device_state(_device, target_state)
        self._build_tree()

    def _update_tree(self):
        """
        Checks to see if the size of the list of USB devices has changed
        and if it has, refresh the tree header and list of devices.

        :return: None
        """
        _latest_list = get_usb_devices()
        if collections.Counter(_latest_list) != collections.Counter(self.current_list):
            self.current_list = _latest_list
            self._build_headers()
            self._build_tree()
        self.list_frame.after(1000, self._update_tree)

    def _sort_by(self, col, descending):
        """
        Sorts tree contents when a column header is clicked on.

        :param col: The column to sort on
        :param descending: True if descending, False if ascending sort
                           desired
        :return: None
        """
        data = [(self.tree.set(child, col), child) for child in self.tree.get_children('')]
        # Sort the data in place
        # if the data to be sorted is numeric change to float
        # data = change_numeric(data)
        data.sort(reverse=descending)
        for ix, item in enumerate(data):
            self.tree.move(item[1], '', ix)
        # Switch the sort direction
        self.tree.heading(col,
                          command=lambda c=col:
                          self._sort_by(col, int(not descending)))


def get_usb_devices() -> list:
    """Returns list of USB devices that are eligible for binding
    and unbinding. Devices with 'hub' in the description are excluded
    from the list.  The returned list consists of tuples, with each
    tuple containing the USB device ID, Tag (Product description), Device
    number, and state. State is "Enabled" if device is bound, "Disabled"
    if unbound.

    :return: List of tuples of USB devices. If no devices were found,
             returns empty list.
    """
    import re
    device_re = re.compile("Bus\\s+(?P<bus>\\d+)\\s+"
                           "Device\\s+(?P<device>\\d+).+"
                           "ID\\s(?P<id>\\w+:\\w+)\\s(?P<tag>.+)$", re.I)
    devices = []
    try:
        df = subprocess.check_output("lsusb").decode('utf-8')
    except subprocess.CalledProcessError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return devices
    for i in df.split('\n'):
        hub = True  # Assume device is a hub
        if i:
            info = device_re.match(i)
            if info:
                dinfo = info.groupdict()
                _bus = dinfo.pop('bus')
                _device = dinfo.pop('device')
                # See if the device is a hub. Ignore it if it is
                cmd = f"sudo lsusb -D /dev/bus/usb/{_bus}/{_device} 2>/dev/null | grep -qi 'bDeviceClass.*Hub'"
                try:
                    subprocess.check_output(cmd, shell=True).decode('utf-8')
                except subprocess.CalledProcessError:
                    hub = False  # Did not find 'Hub' in 'nDeviceClass'
                if hub:  # Device is a hub, so skip it.
                    continue
                cmd = f"grep -l {_bus}/{_device} /sys/bus/usb/devices/*/uevent 2>/dev/null | tail -1"
                try:
                    product = subprocess.check_output(cmd, shell=True).decode('utf-8')
                except subprocess.CalledProcessError as e:
                    print(f"ERROR: {e}", file=sys.stderr)
                    continue
                if product:
                    _p = product.split('/')[5]
                    if os.path.islink(f"/sys/bus/usb/drivers/usb/{_p}"):
                        status = "Enabled"
                    else:
                        status = 'Disabled'
                    devices.append((dinfo['id'], dinfo['tag'],
                                    _p, status))
    return devices


def set_usb_device_state(_device: str, _action: str) -> bool:
    """
    Binds (enables) or unbinds (disables) a USB device

    :param _device: Device designation
    :param _action: bind|unbind Desired setting for device
    :return True if _action was successful, False otherwise
    """
    cmd = f"echo {_device} | sudo tee /sys/bus/usb/drivers/usb/{_action} 2>/dev/null"
    try:
        _result = subprocess.check_output(cmd, shell=True).decode('utf-8')
    except subprocess.CalledProcessError as e:
        print(f"ERROR: {e}. Do you have sudo permissions to run "
              f"'sudo tee /sys/bus/usb/drivers/usb/{_action}'?",
              file=sys.stderr)
        return False
    else:
        return True


def find_usb_device(_device_string: str, _action: str) -> bool:
    """
    Searches the ID and tag for device_string, and if a match is
    found, calls set_usb_device_state to bind/unbind that USB device.

    :param _device_string: String to search for in USB device ID or Tag
                            (Product string)
    :param _action: bind|unbind Desired setting for device
    :return True if device was found AND _action was successful, False
            otherwise
    """
    devices = get_usb_devices()
    if devices:
        for d in devices:
            if _device_string.casefold() in d[0].casefold() or \
                    _device_string.casefold() in d[1].casefold():
                if (_action == "bind" and d[3] == "Enabled") or \
                        (_action == "unbind" and d[3] == "Disabled"):
                    print(f"ERROR: {_action} requested but device is already {d[3]}",
                          file=sys.stderr)
                    return False
                _answer = set_usb_device_state(d[2], _action)
                if _answer:
                    return True
                else:
                    return False
    return False


def sigint_handler(sig, frame):
    print(f"Signal handler caught {sig} {frame}")
    root.quit()


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(prog='usb_control.py',
                                     description=f"USB Device Control")
    parser.add_argument('-v', '--version', action='version',
                        version=f"Version: {__version__}")
    parser.add_argument("-l", "--list", action='store_true',
                        help="list available non-hub USB devices")
    parser.add_argument("-b", "--bind",
                        type=str, metavar="STRING",
                        help="bind (enable) a usb device containing "
                             "STRING (case-insensitive) in 'lsusb' "
                             "output ID or Tag fields")
    parser.add_argument("-u", "--unbind",
                        type=str, metavar="STRING",
                        help="unbind (disable) a usb device containing "
                             "STRING (case-insensitive) in 'lsusb' "
                             "output ID or Tag fields")
    arg_info = parser.parse_args()
    if not sys.platform.startswith('linux'):
        print(f"ERROR: This application only works on Linux", file=sys.stderr)
        sys.exit(1)
    if arg_info.list:
        dev_list = get_usb_devices()
        if dev_list:
            try:
                from tabulate import tabulate
            except ModuleNotFoundError:
                print("ERROR: Python3 'tabulate' module required. Run 'sudo "
                      "apt update && sudo apt install python3-tabulate' "
                      "to install it.", file=sys.stderr)
                sys.exit(1)
            else:
                print(tabulate(dev_list, headers=["ID", "Tag", "Device", "State"]))
                sys.exit(0)
        else:
            print("No non-hub USB devices found", file=sys.stderr)
            sys.exit(0)
    if arg_info.bind:
        answer = find_usb_device(arg_info.bind, "bind")
        if answer:
            sys.exit(0)
        else:
            sys.exit(1)
    if arg_info.unbind:
        answer = find_usb_device(arg_info.unbind, "unbind")
        if answer:
            sys.exit(0)
        else:
            sys.exit(1)

    # If we made it this far, no arguments were supplied. Attempt
    # to open GUI.
    if os.environ.get('DISPLAY', '') == '':
        print(f"ERROR: No $DISPLAY environment. "
              f"Must supply argument to run without X", file=sys.stderr)
        sys.exit(1)
        # os.environ.__setitem__('DISPLAY', ':0.0')

    root = tk.Tk()
    root.resizable(width=True, height=True)
    signal.signal(signal.SIGINT, sigint_handler)
    # Stop program if Esc key pressed
    root.bind('<Escape>', lambda _: root.quit())
    # Stop program if window is closed at OS level ('X' in upper right
    # corner or red dot in upper left on Mac)
    root.protocol("WM_DELETE_WINDOW", lambda: root.quit())
    UsbWindow(root)
    root.mainloop()
    sys.exit(0)
