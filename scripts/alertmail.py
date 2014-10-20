#!/usr/bin/python
import smtplib
import os

toaddr='capveg@cs.umd.edu'
fromaddr='capveg@cs.umd.edu'

msg = ( "From: %s\r\nTo: %s\r\nSubject: ALERT!\r\n\r\nPassenger is down\r\n%s\r\n" 
	% (fromaddr, toaddr,os.uname()))


server = smtplib.SMTP('dispatch.cs.umd.edu')
#server.set_debuglevel(1)
server.sendmail(fromaddr,toaddr,msg)
server.quit()
