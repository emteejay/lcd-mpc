#!/bin/sh
# player.tcl \
exec tclsh "$0" ${1+"$@"}

# =============================================================================
#
#  Simple mpd client for LCDd
#  Copyright 2009-2013 Martin Tharby Jones martin@brasskipper.org.uk
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# =============================================================================

# Settings that may need to be changed

# Where the display daemon LCDd is running
#set lcdhost localhost
set lcdhost LiFi.local
# The port to use for the display daemon LCDd
set lcddport 13666

# Where the music player daemon mpd is running
set mpdhost localhost
#set mpdhost LiFi.local
#set mpdhost Ace.local
# The port to use for the player daemon mpd
set mpdport 6600

# Where to display the song details
set line(Artist) 1
set line(Album) 3
set line(Title) 2
set line(time) 4

# Keys for the picoLCD: http://www.mini-box.com/picoLCD-20x2-OEM
# in units such as the M300 http://www.mini-box.com/Mini-Box-M300-LCD
# Unused keys: Left Right Up Down Enter
set keysUsed "Plus Minus F1 F2 F3 F4 F5"

# Specify the function performed by each key
set keyFunction(Plus) volumeUp
set keyFunction(Minus) volumeDown
set keyFunction(F1) previous
set keyFunction(F2) pause
set keyFunction(F3) stop
set keyFunction(F4) play
set keyFunction(F5) next

# The picoLCD also has an IR remote control receiver.
set keysUsed "$keysUsed Previous Next Play PlayPause Pause Stop"
set keyFunction(Next) next
set keyFunction(Pause) pause
set keyFunction(PlayPause) pause
set keyFunction(Play) play
set keyFunction(Previous) previous
set keyFunction(Stop) stop

# The keys may be illuminated by setting the appropriate output bit
set keyLED(unknown) 0
set keyLED(OK) 1
set keyLED(previous) 2
set keyLED(pause) 4
set keyLED(stop) 8
set keyLED(play) 16
set keyLED(next) 32

# Indicate how to light the keys
set brightMode "on"

# ==============================================================================

# Shut down everything tidily.
# Close the music player and display sockets then exit.
proc cleanExit {exitcode description} {
    global lcdsock mpdsock
    catch {close $lcdsock}
    catch {close $mpdsock}
    puts $description
    exit $exitcode
}

# ------------------------------------------------------------------------------
# The severity of debug message to report
set debugLevel 2
# Output debug messages
proc debug {level string} {
    if {$level <= $::debugLevel} {
        puts  $string
    }
}

# ------------------------------------------------------------------------------
# Perform an action repeated at the specifed interval
proc every {ms body} {
    eval $body
    after $ms [list every $ms $body]
}

# ==============================================================================
# Procedures for handling the Music Player Deamon (mpd)

# Delay between updates in ms, mpd closes the socket if it is idle for 60 seconds
set updatetime 1000

# Status of the music player mpd
set mpdstatus(version) "unknown"
set mpdstatus(state) "unknown"
set mpdstatus(songid) "unknown"
set mpdstatus(consume) 0
set mpdstatus(random) 0
set mpdstatus(repeat) 0
set mpdstatus(single) 0
set mpdstatus(volume) 25
set mpdstatus(playListsUpdate) 0


# ------------------------------------------------------------------------------
# Establish the socket connection to the music player
proc connectMpd {} {
    if {[catch {set ::mpdsock [socket $::mpdhost $::mpdport]}]} {
        cleanExit 1 "Error connecting to mpd on $::mpdhost:$::mpdport"
    }
    fileevent $::mpdsock readable [list mpdSockRead]
}

# ------------------------------------------------------------------------------
# Send commands to the music player
proc sendToMpd {string} {
    global mpdsock mpdstatus

    if {$::mpdstatus(version) == "unknown"} {
        connectMpd
    }
    puts $mpdsock $string
    if {$string != "status"} {
        debug 3 "mpd <- $string"
    } else {
        debug 4 "mpd <- $string"
    }
    flush $mpdsock
}

# ------------------------------------------------------------------------------
# Process data from the music player
proc mpdSockRead {} {
    global mpdsock mpdstatus line

    gets $mpdsock lineRead
    debug 4 "mpd -> $lineRead"

    if {$lineRead == ""} {
        # TODO menu control of connection?
        cleanExit 2 "mpd closed our connection, bye."
    }

    if {[string match {OK MPD*} $lineRead]} {
        set list [split $lineRead]
        set mpdstatus(version) [lindex $list 2]
        # mpd only provides limited events so poll.
        every $::updatetime "sendToMpd status"
    }

    set list  [split $lineRead :]
    set param [lindex $list 0]
    # set values [join [lrange $list 1 end] ":"]
    set value [string trim [lindex $list 1]]
    switch $param {
        state {
            if {$mpdstatus(state) != $value} {
                switch $value {
                    play {
                        # Ask mpd about the current song
                        sendToMpd "currentsong"
                        setButton play
                        sendToLCDd "screen_set mini_mpc -priority foreground"
                        sendToLCDd "screen_set mpc_title -priority hidden"
                                        }
                    pause {
                        setButton pause
                        sendToLCDd "screen_set mpc_title -priority info"
                        sendToLCDd "screen_set mini_mpc -priority hidden"
                    }
                    stop {
                        setButton stop
                        sendToLCDd "screen_set mpc_title -priority info"
                        sendToLCDd "screen_set mini_mpc -priority hidden"
                    }
                }
            }
            set mpdstatus(state) $value
        }
        Artist {
            set mpdstatus($param) $value
            updatelLine $line(Artist) $value
            debug 2 "Artist: $value"
        }
        Title {
            set mpdstatus($param) $value
            updatelLine $line(Title) $value
            debug 2 " Title: $value"
       }
        Album {
            set mpdstatus($param) $value
            updatelLine $line(Album) $value
            debug 2 " Album: $value"
        }
        Composer {
            set mpdstatus($param) $value
            # updatelLine $line(Composer) $value
            debug 2 " Composer: $value"
        }
        duration -
        time {
            set mpdstatus($param) $value
            set mpdstatus(trackTime) [string trim [lindex $list 2]]
            updatelLine $line(time) "$value/$mpdstatus(trackTime)"
        }
        songid {
            if {$mpdstatus(songid) != $value} {
                # Ask mpd about the new song
                sendToMpd "currentsong"
                set mpdstatus(songid) $value
            }
        }
        consume -
        random -
        repeat -
        single {
            if {$mpdstatus($param) != $value} {
                if {$value} {
                    sendToLCDd "menu_set_item \"\" $param -value on"
                } else {
                    sendToLCDd "menu_set_item \"\" $param -value off"
                }
                set mpdstatus($param) $value
            }
        }
        playlist {
            if {$mpdstatus(playListsUpdate) == 1} {
                debug 4 "Adding playlist $value"
                lappend mpdstatus(playLists) $value
                debug 4 "Playlists is now $mpdstatus(playLists)"
            }
        }
        OK {
            if {$mpdstatus(playListsUpdate) == 1} {
                set mpdstatus(playListsUpdate) 0
                set playLists [join $mpdstatus(playLists) \t]
                sendToLCDd "menu_set_item \"\" playList -strings \"$playLists\""
            }
        }
        ACK {
            # report what went wrong
            debug 1 "mpd -> $lineRead"
        }
        error {
            # report why mpd is complaining
            debug 1 "mpd -> $lineRead"
        }
        AlbumArtist -
        AlbumArtistSort -
        ArtistSort -
        audio -
        bitrate -
        Date -
        Disc -
        elapsed -
        file -
        Genre -
        Id -
        Label -
        mixrampdb -
        nextsong -
        nextsongid -
        playlistlength -
        Pos -
        song -
        Time -
        Track -
        volume -
        xfade {
            set mpdstatus($param) $value
        }
        Last-Modified -
        MUSICBRAINZ_ALBUMID -
        MUSICBRAINZ_ALBUMARTISTID -
        MUSICBRAINZ_ARTISTID -
        MUSICBRAINZ_TRACKID
        {
        }
        default {
            #report unexpected responses
            debug 1 "mpd -> $lineRead"
        }
    }
}

# ------------------------------------------------------------------------------
# Adding a playlist to the stored playlists list:-
# The 'playlist' token is used with different meanings
# in the 'status' and 'listplaylists' responses.
#
# -> status
# ...
# <- playlist: 17
# ...
# <- OK
# -> listplaylists
# <- playlist: Rock
# <- Last-Modified: 2012-12-21T18:04:08Z
# ...
# <- OK


# ==============================================================================
# Procedures for handling the display


# ------------------------------------------------------------------------------
# Flag indicating when a menu is entered
set clientMenu 0

# ------------------------------------------------------------------------------
# Send commands to the LCDproc deamon
proc sendToLCDd  {string} {
    global lcdsock
    debug 3 "lcd <- $string"
    puts $lcdsock $string
    flush $lcdsock
}

# ------------------------------------------------------------------------------
# Open a socket connection to the display daemon LCDd, set a procedure to
# read data from the display and say "hello".
proc connectLcd {} {
    global lcdhost lcddport lcdsock
    set attempt 0

    while {[catch {set lcdsock [socket $lcdhost $lcddport]}]} {
        if {6 < $attempt} {
            cleanExit 3 "Error connecting to LCDd on $lcdhost:$lcddport"
        }
        puts "LCDd not ready  $attempt"
        incr attempt
        exec sleep 10
    }
    fileevent $lcdsock readable [list lcdSockRead]

    sendToLCDd "hello"
}

# ------------------------------------------------------------------------------
# Read and process data from the display daemon LCDd.
proc lcdSockRead {} {
    global lcdsock lcd screenactive

    gets $lcdsock line

    if {$line == ""} {
        cleanExit 4 "LCDd died, bye."
    }

    debug 3 "lcd -> $line"

    switch -glob $line {
        connect* {
            set list [split $line]
            set lcd(version) [lindex $list 2]
            set lcd(prot) [lindex $list 4]
            set lcd(width) [lindex $list 7]
            set lcd(height) [lindex $list 9]
            set lcd(charWidth) [lindex $list 11]
            set lcd(charHeight) [lindex $list 13]
            addLCDScreens $lcd(height)
            foreach key [split $::keysUsed] {
                sendToLCDd "client_add_key -shared $key"
            }
            debug 2 "lcd -> [lrange $list 0 4]"
        }
        ignore* {
            set screenactive 0
            if {$::clientMenu == 0} {
                sendToLCDd "menu_set_main _main_"
            }
            setButton unknown
        }
        listen* {
            set screenactive 1
            sendToLCDd "menu_set_main \"\""
            setButton $::mpdstatus(state)
        }
        key* {
            handleKey $line
        }
        menuevent* {
            handleMenu $line
        }
        success* {
        }
        default {
            debug 1 "lcd -> $line"
        }
    }
}

# ------------------------------------------------------------------------------
# Add and configure screens and widgets on the display
proc addLCDScreens {height} {
    sendToLCDd "client_set name \"Music Player\""
    # Screen when not playing -----------------------
    sendToLCDd "screen_add mpc_title"
    sendToLCDd "screen_set mpc_title -name mpc_title"
    sendToLCDd "screen_set mpc_title -priority info"
    sendToLCDd "widget_add mpc_title title title"
    sendToLCDd "widget_set mpc_title title \"Music Player\""
    # Key labels ------------------------------------
    sendToLCDd "widget_add mpc_title prev  icon"
    sendToLCDd "widget_set mpc_title prev  1 2 PREV"
    sendToLCDd "widget_add mpc_title pause icon"
    sendToLCDd "widget_set mpc_title pause 6 2 PAUSE"
    sendToLCDd "widget_add mpc_title stop  icon"
    sendToLCDd "widget_set mpc_title stop  10 2 STOP"
    sendToLCDd "widget_add mpc_title play  icon"
    sendToLCDd "widget_set mpc_title play  15 2 PLAY"
    sendToLCDd "widget_add mpc_title next  icon"
    sendToLCDd "widget_set mpc_title next  19 2 NEXT"
    # Screen when playing----------------------------
    sendToLCDd "screen_add mini_mpc"
    sendToLCDd "screen_set mini_mpc -name mini_mpc"
    sendToLCDd "screen_set mini_mpc -heartbeat off"
    sendToLCDd "screen_set mini_mpc -priority hidden"
    for {set i 1} {$i <= $height} {incr i} {
        sendToLCDd "widget_add mini_mpc line$i scroller"
    }
    # Screen for adjusting volume---------------------
    sendToLCDd "screen_add mini_vol"
    sendToLCDd "screen_set mini_vol -name mini_mpd_vol"
    sendToLCDd "screen_set mini_vol -heartbeat off"
    sendToLCDd "screen_set mini_vol -priority hidden"
    sendToLCDd "widget_add mini_vol Volume title"
    sendToLCDd "widget_add mini_vol volstr string"
    sendToLCDd "widget_add mini_vol volume hbar"
    # Menu items-------------------------------------
    sendToLCDd "menu_add_item \"\" bright checkbox \"Bright mode\""
    sendToLCDd "menu_add_item \"\" consume checkbox \"Consume\""
    sendToLCDd "menu_add_item \"\" random checkbox \"Random\""
    sendToLCDd "menu_add_item \"\" repeat checkbox \"Repeat\""
    sendToLCDd "menu_add_item \"\" single checkbox \"Single\""
    sendToLCDd "menu_add_item \"\" volume slider \"Volume\" -minvalue \"0\" -maxvalue \"100\""
    sendToLCDd "menu_add_item \"\" playList ring \"Play:\" -strings \"\""
    sendToLCDd "menu_add_item \"\" loadList action \"Load Play List\""
    sendToLCDd "menu_add_item \"\" clearQueue action \"Clear Play Queue\""
}

# ------------------------------------------------------------------------------
# Process key press events reported by the display daemon LCDd.
proc handleKey {line} {
    global mpdstatus keyFunction
    set list [split $line]
    set key [lindex $list 1]
   debug 2 "lcd: $key"
    switch $keyFunction($key) {
        volumeUp {
            incr mpdstatus(volume) 2
            if {100 < $mpdstatus(volume)} {
                set mpdstatus(volume) 100
            }
            setVolume $mpdstatus(volume)
        }
        volumeDown {
            incr mpdstatus(volume) -2
            if {$mpdstatus(volume) < 0} {
                set mpdstatus(volume) 0
            }
            setVolume $mpdstatus(volume)
        }
        stop {
            sendToMpd stop
            debug 2 "⏹"
        }
        pause -
        play {
            switch $mpdstatus(state) {
                play {
                    sendToMpd pause
                    debug 2 "⏸"
                }
                pause -
                stop {
                    sendToMpd play
                    debug 2 "⏵"
                }
                unknown {
                    sendToMpd status
                }
            }
        }
        previous {
            setButton previous
            sendToMpd previous
            set mpdstatus(state) "unknown"
            debug 2 "⏮"
        }
        next {
            setButton next
            sendToMpd next
            set mpdstatus(state) "unknown"
            debug 2 "⏭"
        }
    }
}

# ------------------------------------------------------------------------------
# Process menu events reported by the display daemon LCDd.
proc handleMenu {line} {
    global mpdstatus
    set list [split $line]
    set action [lindex $list 1]
    set item   [lindex $list 2]
    set value  [lindex $list 3]
    debug 4 "handleMenu Action: \"$action\", Item: \"$item\", Value: \"$value\""
    switch $item {
        _client_menu_ {
            switch $action {
                enter {
                    set ::clientMenu 1
                    set ::screenactive 1
                    sendToLCDd "menu_set_item \"\" bright -value $::brightMode"
                    foreach item {consume random repeat single} {
                        if {$mpdstatus($item)} {
                            sendToLCDd "menu_set_item \"\" $item -value on"
                        } else {
                            sendToLCDd "menu_set_item \"\" $item -value off"
                        }
                    }
                    sendToLCDd "menu_set_item \"\" volume -value $mpdstatus(volume)"
                    if {[info exists mpdstatus(playLists)]} {
                        unset mpdstatus(playLists)
                    }
                    sendToMpd "listplaylists"
                    set mpdstatus(playListsUpdate) 1
                }
                leave {
                    set ::clientMenu 0
                    set ::screenactive 0
                }
            }
        }
        consume -
        random -
        repeat -
        single {
            if {$value == "on"} {
                set state 1
            } else {
                set state 0
            }
            sendToMpd "$item $state"
        }
        bright {
            set ::brightMode $value
        }
        volume {
            switch $action {
                enter {
                    sendToLCDd "menu_set_item \"\" volume -value $mpdstatus(volume)"
                }
                minus -
                plus {
                    sendToMpd "setvol $value"
                }
            }
        }
        playList {
            debug 4 "handleMenu: $line"
            set mpdstatus(playListIndex) $value
        }
        loadList {
            if {[info exists mpdstatus(playLists)] && [info exists mpdstatus(playListIndex)] } {
                sendToMpd "load [lindex $mpdstatus(playLists) $mpdstatus(playListIndex)]"
            }
        }
        clearQueue {
            sendToMpd "clear"
        }
        default {
            debug 1 "handleMenu: $line"
        }
    }
}

# Identity of command to remove volume display from screen
set vId 0

# ------------------------------------------------------------------------------
# Adjust the volume and display the current level on the screen
proc setVolume {level} {
    after cancel $::vId
    sendToMpd "setvol $level"
    sendToLCDd "screen_set mini_vol -priority input"
    sendToLCDd "widget_set mini_vol volstr 1 1 \"Volume $level%\""
    # Display a horizontal bar length pixels wide
    set hb_length [expr $::lcd(width) * $::lcd(charWidth) * $level / 100]
    sendToLCDd "widget_set mini_vol volume 1 2 $hb_length"
    # Reset priority after a timeout
    set ::vId [after 5000 "sendToLCDd \"screen_set mini_vol -priority hidden\""]
}

# ------------------------------------------------------------------------------
# Set a line on the display
proc updatelLine {position text} {
    global line
    set line($position) $text
    if {$position <= $::lcd(height)} {
        if {[string length $text] < 25} {
            set sMode h
        } else {
            set sMode m
            set text "$text * "
        }
        set text [regsub -all \" $text \\\"]
        debug 4 "$position $text"
        sendToLCDd "widget_set mini_mpc line$position 1 $position 20 $position $sMode 1 \"$text\""
    }
}

# ------------------------------------------------------------------------------
# Illuminate the required buttons
proc setButton {button} {
    if {$::screenactive} {
        if {$::brightMode == "on"} {
            set outputValue [expr 63 - $::keyLED($button)]
        } else {
            set outputValue $::keyLED($button)
        }
        sendToLCDd "output $outputValue"
    }
}

# ==============================================================================

set line($line(Artist)) Artist
set line($line(Album)) Album
set line($line(Title)) Title
set line($line(time)) "Time"

# ==============================================================================
# Setup the connections then enter the event loop
connectLcd
vwait screenactive
#connectMpd
vwait forever
