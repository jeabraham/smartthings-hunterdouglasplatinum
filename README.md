# Hunter Douglas Platinum Gateway Integration with SmartThings Hub

Forked from https://github.com/schwark/smartthings-hunterdouglasplatinum


## Step 1: Get your blinds and your Platinum Gateway working with the Platinum App on your phone

This SmartThings integration doesn't support setting up your Platinum Gateway.  You 
need to do that [using your phone](https://apps.apple.com/us/app/platinum-app/id556728718?ign-mpt=uo%3D4).  You should set up the gateway, give it a static IP
address using your router, and then join your blinds to the gateway using the instructions
in the dedicated app (also in the docs directory).  Set up your "rooms" (which are groups of shades/blinds) and also any "scenes" you want.


## Step 2: Install the SmartApp.  

[Github integration](http://docs.smartthings.com/en/latest/tools-and-ide/github-integration.html) is working again with this version, so you should be able to add 
my repo to your IDE in SmartThings, and then "update from repo" to pull in the SmartApp.
Be sure to also "Update from Repo" to pull in the device drivers. Note that my repo
is under my namespace jeabraham, but when you're pulling from it into SmartThings it will still show up under the @schwark 
namespace out of respect from the original author. 

## Step 3: Get the configuration file and host it somewhere.

Unfortunately, this SmartApp cannot query the Platinum Gateway to discover your
blinds and scenes.  You need to "telnet" into the Platinum Gateway and type 
`$dat` into the telnet session. @schwark has written a python program to do this for you,
which is great if you have python.  Or, you can use netcat or telnet:

netcat:

	nc -i3 <ip-address-of-gateway> 522 < input.txt > output.txt

telnet on Windows:

	telnet -f output.txt <ip-address-of-gateway> 522 < input.txt

python:
	
	python getstatus.py <ip-address-of-gateway> > output.txt

Any of these commands will give you an output.txt file that describes your blinds. 
The SmartApp needs to find this file using a web request.  If you have a webserver running on your internal network, you can host it there. You may be able to use pastbin, apparently it supports downloading 'raw' files (you need to use the "raw" link to the file, not the standard link to the file.) Dropbox no longer supports 'raw' links, Dropbox will put a bunch of http around your output.txt file and the SmartApp won't be able to interpret it.  Maybe you have a wordpress site or have access to your company's website, and you can quietly host a little file on it at a hidden URL no-one will ever find.  

## Step 4: Install the SmartApp in SmartThings using your phone.

Turn on Live Logging in the IDE, so you can watch for progress and any errors.  Then, in the SmartThings Classic app on your phone, add an instance of the Hunter Douglas Platinum Gateway app.  You need to tell it the Gateway IP address, as well as the Gateway
Status URL where you are hosting your output.txt file.  Within 5 minutes it should be
parsing your configuration file from your website, and it will add your scenes, and your blinds if you selected "Do you want to add each Shade as a Switch?" when you installed the App.  


# Future directions

This version gives each shade two sliders, the second one is only useful for Nantucket and Silhouette shades that can swivel the vanes.  It would be nice if it inspected the shade
type, and didn't install the extra slider for other shade types.

In the docs folder is an app for the Mi Casa Verde system, that is much more complete. There are many more possibilities.  It listens for acknowledgements after each command, to avoid queueing them too fast.  This means that it can listen to responses via telnet.  

Manually updating the output.txt file (using `telnet`, `netcat`, or the provided python utility `getstatus.py`) that describes your blinds and scenes, and hosting
it on a webserver, is a big challenge for most people. It should be possible for the
SmartApp to query the gateway directly for this information, using telnet.  @schwark said:

`Since I could not get SmartThings hub to return the result of a TCP query on a local network, you have to telnet or netcat or run the python script included, to your gateway to get one file and put it up on a web accessible page and enter that URL in as a Status URL.`



## Bugs

There seems to be a problem updating a shade or scene.  Watch for errors in the logging 
complaining about unique IDs.  If this happens, You can delete your shades and scenes, and they'll be
recreated within 5 minutes by the SmartApp. 

