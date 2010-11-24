# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2010 Kenneth Lavrsen, kenneth@lavrsen.dk
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# For licensing info read LICENSE file in the Foswiki root.

=pod

---+ package TimeCalcPlugin

__NOTE:__ When writing handlers, keep in mind that these may be invoked
on included topics. For example, if a plugin generates links to the current
topic, these need to be generated before the afterCommonTagsHandler is run,
as at that point in the rendering loop we have lost the information that we
the text had been included from another topic.

=cut

package Foswiki::Plugins::TimeCalcPlugin;


# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Func    ();    # The plugins API
use Foswiki::Plugins ();    # For the API version
use Time::Local;

# $VERSION is referred to by Foswiki, and is the only global variable that
# *must* exist in this package. This should always be in the format
# $Rev: 9771 $ so that Foswiki can determine the checked-in status of the
# extension.
our $VERSION = '$Rev: 9771 $';

# $RELEASE is used in the "Find More Extensions" automation in configure.
# It is a manually maintained string used to identify functionality steps.
# You can use any of the following formats:
# tuple   - a sequence of integers separated by . e.g. 1.2.3. The numbers
#           usually refer to major.minor.patch release or similar. You can
#           use as many numbers as you like e.g. '1' or '1.2.3.4.5'.
# isodate - a date in ISO8601 format e.g. 2009-08-07
# date    - a date in 1 Jun 2009 format. Three letter English month names only.
# Note: it's important that this string is exactly the same in the extension
# topic - if you use %$RELEASE% with BuildContrib this is done automatically.
our $RELEASE = '1.1';

# Short description of this plugin
# One line description, is shown in the %SYSTEMWEB%.TextFormattingRules topic:
our $SHORTDESCRIPTION = 'Perform calculations on time and dates';

# You must set $NO_PREFS_IN_TOPIC to 0 if you want your plugin to use
# preferences set in the plugin topic. This is required for compatibility
# with older plugins, but imposes a significant performance penalty, and
# is not recommended. Instead, leave $NO_PREFS_IN_TOPIC at 1 and use
# =$Foswiki::cfg= entries, or if you want the users
# to be able to change settings, then use standard Foswiki preferences that
# can be defined in your %USERSWEB%.SitePreferences and overridden at the web
# and topic level.
#
# %SYSTEMWEB%.DevelopingPlugins has details of how to define =$Foswiki::cfg=
# entries so they can be used with =configure=.
our $NO_PREFS_IN_TOPIC = 1;

# Storage hash for the user defined variables
my %storage;

# hash of working days
my %workingDays;

=begin TML

---++ initPlugin($topic, $web, $user) -> $boolean
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$user= - the login name of the user
   * =$installWeb= - the name of the web the plugin topic is in
     (usually the same as =$Foswiki::cfg{SystemWebName}=)

*REQUIRED*

Called to initialise the plugin. If everything is OK, should return
a non-zero value. On non-fatal failure, should write a message
using =Foswiki::Func::writeWarning= and return 0. In this case
%<nop>FAILEDPLUGINS% will indicate which plugins failed.

In the case of a catastrophic failure that will prevent the whole
installation from working safely, this handler may use 'die', which
will be trapped and reported in the browser.

__Note:__ Please align macro names with the Plugin name, e.g. if
your Plugin is called !FooBarPlugin, name macros FOOBAR and/or
FOOBARSOMETHING. This avoids namespace issues.

=cut

sub initPlugin {
    my( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    Foswiki::Func::registerTagHandler( 'WORKINGDAYS', \&_WORKINGDAYS );
    Foswiki::Func::registerTagHandler( 'ADDWORKINGDAYS', \&_ADDWORKINGDAYS );
    Foswiki::Func::registerTagHandler( 'TIMESHOWSTORE', \&_TIMESHOWSTORE );

    # Plugin correctly initialized
    return 1;
}

sub _returnNoonOfDate {
    my ( $indate ) = @_;
    
    my ( $sec, $min, $hour, $day, $mon, $year, $wday, $yday ) = gmtime($indate);
    return timegm( 0, 0, 12, $day, $mon, $year );
}

sub _loadWorkingDays {
    # We assume there is at least one working day in a week so no empty string
    my $config = Foswiki::Func::getPreferencesValue('TIMECALCPLUGIN_WORKINGDAYS') ||
                 $Foswiki::cfg{TimeCalcPlugin}{WorkingDays} ||
                 "Monday, Tuesday, Wednesday, Thursday, Friday";
    my $i = 0;
    my $count = 0;
    my @weekdays = ( 'Sunday', 'Monday', 'Tuesday', 'Wednesday',
                     'Thursday', 'Friday', 'Saturday' );
    foreach my $weekday ( @weekdays) {
        $workingDays{ $i } = $config =~ /$weekday/i;
        $count++ if $workingDays{ $i };
        $i++;
    }
    $workingDays{ 'count' } = $count;
    return 1;
}

sub _WORKINGDAYS {
    my($session, $params, $theTopic, $theWeb) = @_;
    # $session  - a reference to the Foswiki session object
    #             (you probably won't need it, but documented in Foswiki.pm)
    # $params=  - a reference to a Foswiki::Attrs object containing 
    #             parameters.
    #             This can be used as a simple hash that maps parameter names
    #             to values, with _DEFAULT being the name for the default
    #             (unnamed) parameter.
    # $topic    - name of the topic in the query
    # $web      - name of the web in the query
    # $topicObject - a reference to a Foswiki::Meta object containing the
    #             topic the macro is being rendered in (new for foswiki 1.1.x)
    # Return: the result of processing the macro. This will replace the
    # macro call in the final text.
    
    # For example, %EXAMPLETAG{'hamburger' sideorder="onions"}%
    # $params->{_DEFAULT} will be 'hamburger'
    # $params->{sideorder} will be 'onions'
    
    # We load $workingDays if this is first time we run
    _loadWorkingDays() unless defined $workingDays{ 0 };
    
    # To do - we need to be able to also accept serialized date
    my $startdate = $params->{startdate};
    if ( defined $startdate ) {
        if ( $startdate =~ /^\s*\$(\w+)/ ) {
            # if storage does exist the startdate is undefined           
            $startdate = $storage{ $1 };
            $startdate = _returnNoonOfDate( $startdate ) if defined $startdate;
        }
        else {   
            $startdate = _returnNoonOfDate( Foswiki::Time::parseTime( $startdate ) );
        }
    }
    $startdate = _returnNoonOfDate( time() ) unless defined $startdate;

    my $enddate = $params->{enddate};
    if ( defined $enddate ) {
        if ( $enddate =~ /^\s*\$(\w+)/ ) {
            # if storage does exist the startdate is undefined           
            $enddate = $storage{ $1 };
            $enddate = _returnNoonOfDate( $enddate ) if defined $enddate;
        }
        else {   
            $enddate = _returnNoonOfDate( Foswiki::Time::parseTime( $enddate ) );
        }
    }
    $enddate = _returnNoonOfDate( time() ) unless defined $enddate;

    my $holidaysin   = defined $params->{holidays} ?
                       $params->{holidays} : '';
    my $includestart = defined $params->{includestart} ?
                       Foswiki::Func::isTrue( $params->{includestart} ) : 0;
    my $includeend   = defined $params->{includeend} ?
                       Foswiki::Func::isTrue( $params->{includeend} ) : 1;
    my $storageBin   = $params->{store};

    # To do - we need to be able to also accept serialized date    
    my %holidays = ();
    if ( $holidaysin ) {
        foreach my $holiday ( split( /\s*,\s*/, $holidaysin ) ) {
            $holidays{ _returnNoonOfDate( Foswiki::Time::parseTime( $holiday ) ) } = 1;
        }
    }

    # Calculate working days between two times.
    # Times are standard system times (secs since 1970).
    # Working days are Monday through Friday (sorry, Israel!)
    # A day has 60 * 60 * 24 = 86400 sec. There can be exceptions to this
    # by a few seconds but in practical life it should be OK.

    # We allow the two dates to be swapped around
    ( $startdate, $enddate ) = ( $enddate, $startdate ) if ( $startdate > $enddate );
    use integer;
    $startdate -= 86400 if $includestart;
    $enddate -= 86400 unless $includeend;
    my $elapsed_days = int( ( $enddate - $startdate ) / 86400 );
    my $whole_weeks  = int( $elapsed_days / 7 );
    my $extra_days   = $elapsed_days - ( $whole_weeks * 7 );
    my $work_days    = $elapsed_days -
                       ( $whole_weeks * ( 7 - $workingDays{ 'count' } ) );

    for ( my $i = 0 ; $i < $extra_days ; $i++ ) {
        my $tempwday = ( gmtime( $enddate - $i * 86400 ) )[6];
        if ( !$workingDays{ $tempwday } ) {
            $work_days--;
        }
    }
    
    foreach my $holiday ( keys %holidays ) {
        my $weekday = ( gmtime( $holiday ) )[6];
        if ( $holiday >= $startdate && $holiday <= $enddate &&
             $workingDays{ $weekday } ) {
           $work_days--;
        }
    }

    return $work_days;

}

sub _ADDWORKINGDAYS {
    my($session, $params, $theTopic, $theWeb) = @_;
    # $session  - a reference to the Foswiki session object
    #             (you probably won't need it, but documented in Foswiki.pm)
    # $params=  - a reference to a Foswiki::Attrs object containing 
    #             parameters.
    #             This can be used as a simple hash that maps parameter names
    #             to values, with _DEFAULT being the name for the default
    #             (unnamed) parameter.
    # $topic    - name of the topic in the query
    # $web      - name of the web in the query
    # $topicObject - a reference to a Foswiki::Meta object containing the
    #             topic the macro is being rendered in (new for foswiki 1.1.x)
    # Return: the result of processing the macro. This will replace the
    # macro call in the final text.

    # For example, %EXAMPLETAG{'hamburger' sideorder="onions"}%
    # $params->{_DEFAULT} will be 'hamburger'
    # $params->{sideorder} will be 'onions'
    
    # We load $workingDays if this is first time we run
    _loadWorkingDays() unless defined $workingDays{ 0 };

    my $formatString = defined $params->{_DEFAULT} ?
                       $params->{_DEFAULT} :
                       $Foswiki::cfg{DefaultDateFormat};

    my $date = $params->{date};
    if ( defined $date ) {
        if ( $date =~ /^\s*\$(\w+)/ ) {
            # if storage does not exist the startdate is undefined           
            $date = $storage{ $1 };
            $date = _returnNoonOfDate( $date ) if defined $date;
        }
        else {   
            $date = _returnNoonOfDate( Foswiki::Time::parseTime( $date ) );
        }
    }
    $date = _returnNoonOfDate( time() ) unless defined $date;


    my $delta        = defined $params->{delta} ? $params->{delta} : 0;
    my $holidaysin   = defined $params->{holidays} ?
                       $params->{holidays} : '';
    my $storageBin   = $params->{store};


    my %holidays = ();
    if ( $holidaysin ) {
        foreach my $holiday ( split( /\s*,\s*/, $holidaysin ) ) {
            $holidays{ _returnNoonOfDate( Foswiki::Time::parseTime( $holiday ) ) } = 1;
        }
    }

    my $direction = $delta < 0 ? -1 : 1;

    while ( $delta !=0 ) {
        $date += $direction * 86400;

        my $tempwday = ( gmtime( $date ) )[6];
        if ( $workingDays{ $tempwday } && !$holidays{ $date } ) {
            $delta -= $direction;
        }
    }
    
    $storage{ $storageBin } = $date if defined $storageBin;

    return Foswiki::Time::formatTime($date, $formatString, gmtime);
}

sub _TIMESHOWSTORE {
    my($session, $params, $theTopic, $theWeb) = @_;
    # $session  - a reference to the Foswiki session object
    #             (you probably won't need it, but documented in Foswiki.pm)
    # $params=  - a reference to a Foswiki::Attrs object containing 
    #             parameters.
    #             This can be used as a simple hash that maps parameter names
    #             to values, with _DEFAULT being the name for the default
    #             (unnamed) parameter.
    # $topic    - name of the topic in the query
    # $web      - name of the web in the query
    # $topicObject - a reference to a Foswiki::Meta object containing the
    #             topic the macro is being rendered in (new for foswiki 1.1.x)
    # Return: the result of processing the macro. This will replace the
    # macro call in the final text.

    # For example, %EXAMPLETAG{'hamburger' sideorder="onions"}%
    # $params->{_DEFAULT} will be 'hamburger'
    # $params->{sideorder} will be 'onions'
    
    my $formatString = defined $params->{_DEFAULT} ?
                       $params->{_DEFAULT} :
                       $Foswiki::cfg{DefaultDateFormat};

    my $datetime = $params->{time};
    if ( defined $datetime ) {
        if ( $datetime =~ /^\s*\$(\w+)/ ) {
            # if storage does not exist the startdate is undefined           
            $datetime = $storage{ $1 };
        }
        else {   
            $datetime = Foswiki::Time::parseTime( $datetime );
        }
    }
    $datetime = time() unless defined $datetime;

    my $storageBin   = $params->{store};
    
    $storage{ $storageBin } = $datetime if defined $storageBin;

    return Foswiki::Time::formatTime($datetime, $formatString, gmtime);
}

1;
