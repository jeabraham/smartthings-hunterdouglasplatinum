Hunter Douglas API Experiments

Closed but vanes open

	1 $cs03-02-07-Front
	1 $cp03-04-255-
	
Closed and vanes closed

Commands sent

	1 $act01-00-
	1 $cp03-07-000-
	1 $act02-02-
	1 $act00-00-

Ending status

	1 $cs03-02-07-Front
	1 $cp03-07-000-
	
Partially closed vanes

	2 $cs03-02-07-Front
	2 $cp03-07-114-
	
Opening vanes

Commands sent

	2 $act01-00-
	2 $cp03-07-255-
	2 $act02-02-
	2 $act00-00-

Ending status

	2 $cs03-02-07-Front
	2 $cp03-07-255-
	
	
Shades 20% open

Commands sent

	2 $act01-00-
	2 $cp03-04-055-
	2 $act02-02-
	2 $act00-00-
	
Ending status

	2 $cs03-02-07-Front
	2 $cp03-04-055-
	
	
Close them again

Sent

	2 $act01-00-
	2 $cp03-04-000-
	2 $act02-02-
	2 $act00-00-

Status

	2 $cs03-02-07-Front
	2 $cp03-04-000-
	
It looks like -04- is the opening and closing of the shades, and -07- is the status of the vanes




# from https://www.avsforum.com/forum/162-home-automation/909721-any-powerrise-hunter-douglas-motorized-shade-experince-here-4.html


$dat
1 $mbc100-100-100-100-
1 $firm01-2018-HD gateway 2.18
1 $MAC0x000000000000-
1 $LEDl064-
1 $upd00-
1 $reset
1 $set006-
1 $ctVt<garbage>
# rooms

1 $cr00-01-0x0150-Living Room
1 $cr01-02-0x0D1A-Master Bedroom
1 $cr02-01-0xF5CA-Office
# shades

1 $cs00-00-06-Living Room 1
1 $cp00-04-000-
1 $cs01-01-04-Master Bedroom 1
1 $cp01-04-000-
1 $cs02-01-01-Master Bedroom 2
1 $cp02-04-000-
1 $cs03-02-05-Office 1
1 $cp03-04-189-
1 $cs04-01-05-Master Bedroom 3
1 $cp04-04-000-
1 $cs05-01-06-Master Bedroom 4
1 $cp05-04-000-
1 $cs06-00-08-Living Room 2
1 $cp06-04-000-
1 $cs07-00-03-Living Room 3
1 $cp07-04-000-
1 $cs08-00-01-Living Room 4
1 $cp08-04-000-
#scenes

1 $cm00-Wake Up
1 $cq00-01-01-
1 $cq00-02-01-
1 $cq00-04-01-
1 $cq00-05-01-
1 $cx00-01-18-053-01-
1 $cm01-All Open
1 $cq01-00-01-
1 $cq01-01-01-
1 $cq01-02-01-
1 $cq01-03-01-
1 $cq01-04-01-
1 $cq01-05-01-
1 $cq01-06-01-
1 $cq01-07-01-
1 $cq01-08-01-
1 $cx01-00-04-255-01-
1 $cx01-01-04-255-01-
1 $cx01-02-04-255-01-
1 $cm02-All Closed
1 $cq02-00-01-
1 $cq02-01-01-
1 $cq02-02-01-
1 $cq02-03-01-
1 $cq02-04-01-
1 $cq02-05-01-
1 $cq02-06-01-
1 $cq02-07-01-
1 $cq02-08-01-
1 $cx02-01-04-000-01-
1 $cx02-02-04-000-01-
1 $cx02-00-04-000-01-
1 $cm03-Living Room Open
1 $cq03-00-01-
1 $cq03-06-01-
1 $cq03-07-01-
1 $cq03-08-01-
1 $cx03-00-04-255-01-
1 $cm04-Office Open
1 $cq04-03-01-
1 $cx04-02-04-255-01-
1 $upd01-

# invoke a scene
$inm04-
1 $act01-00-
1 $cp03-04-255-
1 $act02-02-
1 $act00-00-

# dummy ping
$dmy
1 $ack

# setting a shades state
$pss03-04-125
1 $act01-00-
1 $cp03-04-125-
1 $done
# activates all shades to transition to the previously defined state

$rls
1 $act02-02-
1 $act00-00-

$pss03-04-191
1 $act01-00-
1 $cp03-04-191-
1 $done
$rls
1 $act02-02-
1 $act00-00-

000 is all the way down
255 is all the way up

# 18 is for the middle rail of tdbu shades
$pss04-18-192-                                                                                                                                                        
1 $act01-00-                                                                                                                                    
1 $cp04-18-192-
1 $done
$rls
1 $act02-01-
1 $act00-00-
$pss04-18-255-
1 $act01-00-
1 $cp04-18-255-
1 $done
$rls
1 $act02-01-
1 $act00-00-
$pss04-18-000-
1 $act01-00-
1 $cp04-18-000-
1 $done
$rls
1 $act02-01-
1 $act00-00-

000 is the top at the top
255 is the top all the way down