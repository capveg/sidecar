#!/usr/bin/python
import smtplib
import os

toaddr='aschulm@gmail.com'
fromaddr='aschulm@gmail.com'

msg = ( "From: %s\r\nTo: %s\r\nSubject: ALERT!\r\n\r\nPassenger is down\r\n%s\r\n" 
	% (fromaddr, toaddr,os.uname()))


server = smtplib.SMTP('gsmtp163.google.com')
#server.set_debuglevel(1)
server.sendmail(fromaddr,toaddr,msg)
server.quit()
