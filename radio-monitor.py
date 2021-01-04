#!/usr/bin/env python3

# Monitors the status of a BCM GPIO pin in output and updates
# a label accordingly.  
#

import tkinter
import tkinter.font as tkfont
import argparse
from RPi import GPIO
import time

__author__ = "Steve Magnuson AG7GN"
__copyright__ = "Copyright 2020, Steve Magnuson"
__credits__ = ["Steve Magnuson"]
__license__ = "GPL"
__version__ = "1.0.0"
__maintainer__ = "Steve Magnuson"
__email__ = "ag7gn@arrl.net"
__status__ = "Production"
left_PTT_pin_default = 12
right_PTT_pin_default = 23
title = 'TX/RX Status'
colors=["white", "black", "red", "green", "blue", "cyan", "yellow", "magenta"]

class StatusWindow(object):

    poll_interval = 100

    def __init__(self, iterable=(), **kwargs):
        self.__dict__.update(iterable, **kwargs)
        self.win_title = title
        self.tkroot = tkinter.Tk()
        labelFont = tkfont.Font(family = 'Helvetica', size = 18, weight = 'bold')
        buttonFont = tkfont.Font(family = 'Helvetica', size = 14)
        self.tkroot.geometry("400x160")
        self.tkroot.title(f"{self.win_title} - {__version__}")

        self.set_up_GPIO()

        if GPIO.input(self.left_PTT_pin):
            self.leftRadioStatus = tkinter.Label(self.tkroot, text="Left Radio\nTX", font=labelFont,
                                   bg=self.left_bg_tx_color, fg=self.left_text_color)
        else:
            self.leftRadioStatus = tkinter.Label(self.tkroot, text="Left Radio\nRX", font=labelFont,
                                   bg=self.left_bg_rx_color, fg=self.left_text_color)
        self.leftRadioStatus.pack(padx=10, pady=5, side=tkinter.LEFT, expand=True, fill=tkinter.X)
        if GPIO.input(self.right_PTT_pin):
            self.leftRadioStatus = tkinter.Label(self.tkroot, text="Right Radio\nTX", font=labelFont,
                                   bg=self.right_bg_rx_color, fg=self.right_text_color)
        else:
            self.rightRadioStatus = tkinter.Label(self.tkroot, text="Right Radio\nRX", font=labelFont,
                                   bg=self.right_bg_rx_color, fg=self.right_text_color)
        self.rightRadioStatus.pack(padx=10, pady=5, side=tkinter.RIGHT, expand=True, fill=tkinter.X)

        self.exitButton = tkinter.Button(self.tkroot, text="Quit", command=self.exit,
                                    font=buttonFont, relief="raised")
        self.exitButton.pack(padx=10, pady=5, side=tkinter.BOTTOM)

        self.tkroot.after(self.poll_interval, self.status_handler)

    def set_up_GPIO(self):
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        GPIO.setup(self.left_PTT_pin, GPIO.OUT)
        GPIO.setup(self.right_PTT_pin, GPIO.OUT)

    def exit(self):
        self.tkroot.destroy()
        GPIO.cleanup()

    def mainloop(self):
        self.tkroot.mainloop()

    def status_handler(self):
        if GPIO.input(self.left_PTT_pin):
            self.leftRadioStatus.configure(text="Left Radio\nTX", bg=self.left_bg_tx_color)
        else:
            self.leftRadioStatus.config(text="Left Radio\nRX", bg=self.left_bg_rx_color)
        if GPIO.input(self.right_PTT_pin):
            self.rightRadioStatus.configure(text="Right Radio\nTX", bg=self.right_bg_tx_color)
        else:
            self.rightRadioStatus.config(text="Right Radio\nRX", bg=self.right_bg_rx_color)
        self.tkroot.after(self.poll_interval, self.status_handler)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(prog='radio-monitor.py',
                                     description=title,
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('-v', '--version', action='version',
                        version=f"Version: {__version__}")
    parser.add_argument("--left_gpio", type=int,
                        help="Left radio PTT GPIO (BCM numbering)",
                        default=left_PTT_pin_default)
    parser.add_argument("--right_gpio", type=int,
                        help="Right radio PTT GPIO (BCM numbering)",
                        default=right_PTT_pin_default)
    parser.add_argument("--left_text_color", choices=colors,
                        type=str, default="yellow",
                        help="Text color for left radio indicator")
    parser.add_argument("--left_bg_rx_color", choices=colors,
                        type=str, default="green",
                        help="Background color for left radio RX indicator")
    parser.add_argument("--left_bg_tx_color", choices=colors,
                        type=str, default="blue",
                        help="Background color for left radio TX indicator")
    parser.add_argument("--right_text_color", choices=colors,
                        type=str, default="yellow",
                        help="Text color for right radio indicator")
    parser.add_argument("--right_bg_rx_color", choices=colors,
                        type=str, default="green",
                        help="Background color for right radio RX indicator")
    parser.add_argument("--right_bg_tx_color", choices=colors,
                        type=str, default="red",
                        help="Background color for right radio TX indicator")
    arg_info = parser.parse_args()
    win = StatusWindow(left_PTT_pin=arg_info.left_gpio, 
                       right_PTT_pin=arg_info.right_gpio,
                       left_text_color=arg_info.left_text_color,
                       left_bg_rx_color=arg_info.left_bg_rx_color,
                       left_bg_tx_color=arg_info.left_bg_tx_color,
                       right_text_color=arg_info.right_text_color,
                       right_bg_rx_color=arg_info.right_bg_rx_color,
                       right_bg_tx_color=arg_info.right_bg_tx_color)
    win.mainloop()
