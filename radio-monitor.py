#!/usr/bin/env python

# ptt.py
#
#
# Monitors the status of a BCM GPIO pin in output and updates
# a label accordingly.  
#
# Author: Steve Magnuson AG7GN

import Tkinter
import tkFont

from RPi import GPIO
import time

version='0.1.1'
win_title='TX/RX Status '
win_title += version

left_PTT_pin = 12
right_PTT_pin = 23

class StatusWindow:

    poll_interval = 100

    def __init__(self, left_PTT_pin, right_PTT_pin):
        self.left_PTT_pin = left_PTT_pin
        self.right_PTT_pin = right_PTT_pin

        self.tkroot = Tkinter.Tk()
        labelFont = tkFont.Font(family = 'Helvetica', size = 18, weight = 'bold')
        buttonFont = tkFont.Font(family = 'Helvetica', size = 14)
        self.tkroot.geometry("400x160")
        self.tkroot.title(win_title)

        self.set_up_GPIO()

        if GPIO.input(self.left_PTT_pin):
            self.leftRadioStatus = Tkinter.Label(self.tkroot, text="Left Radio\nTX", font=labelFont,
                                   bg="blue", fg="yellow")
        else:
            self.leftRadioStatus = Tkinter.Label(self.tkroot, text="Left Radio\nRX", font=labelFont,
                                   bg="green", fg="yellow")
        self.leftRadioStatus.pack(padx=10, pady=5, side=Tkinter.LEFT, expand=True, fill=Tkinter.X)
        if GPIO.input(self.right_PTT_pin):
            self.leftRadioStatus = Tkinter.Label(self.tkroot, text="Right Radio\nTX", font=labelFont,
                                   bg="red", fg="yellow")
        else:
            self.rightRadioStatus = Tkinter.Label(self.tkroot, text="Right Radio\nRX", font=labelFont,
                                   bg="green", fg="yellow")
        self.rightRadioStatus.pack(padx=10, pady=5, side=Tkinter.RIGHT, expand=True, fill=Tkinter.X)

        self.exitButton = Tkinter.Button(self.tkroot, text="Quit", command=self.exit,
                                    font=buttonFont, relief="raised")
        self.exitButton.pack(padx=10, pady=5, side=Tkinter.BOTTOM)

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
            self.leftRadioStatus.configure(text="Left Radio\nTX", bg="blue")
        else:
            self.leftRadioStatus.config(text="Left Radio\nRX", bg="green")
        if GPIO.input(self.right_PTT_pin):
            self.rightRadioStatus.configure(text="Right Radio\nTX", bg="red")
        else:
            self.rightRadioStatus.config(text="Right Radio\nRX", bg="green")
        self.tkroot.after(self.poll_interval, self.status_handler)

if __name__ == '__main__':
    win = StatusWindow(left_PTT_pin, right_PTT_pin)
    win.mainloop()

