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

# $VERSION is referred to by Foswiki, and is the only global variable that
# *must* exist in this package.
use vars qw( $VERSION $RELEASE $SHORTDESCRIPTION $debug 
             $pluginName $NO_PREFS_IN_TOPIC
           );

# This should always be $Rev: 12445$ so that TWiki can determine the checked-in
# status of the plugin. It is used by the build automation tools, so
# you should leave it alone.
$VERSION = '$Rev: 12445$';

# This is a free-form string you can use to "name" your own plugin version.
# It is *not* used by the build automation tools, but is reported as part
# of the version number in PLUGINDESCRIPTIONS.
$RELEASE = '1.0';

# Short description of this plugin
# One line description, is shown in the %SYSTEMWEB%.TextFormattingRules topic:
$SHORTDESCRIPTION = 'Perform calculations on time and dates';

# You must set $NO_PREFS_IN_TOPIC to 0 if you want your plugin to use preferences
# stored in the plugin topic. This default is required for compatibility with
# older plugins, but imposes a significant performance penalty, and
# is not recommended. Instead, use $Foswiki::cfg entries set in LocalSite.cfg, or
# if you want the users to be able to change settings, then use standard TWiki
# preferences that can be defined in your %USERSWEB%.SitePreferences and overridden
# at the web and topic level.
$NO_PREFS_IN_TOPIC = 0;

# Name of this Plugin, only used in this module
$pluginName = 'TimeCalcPlugin';

=pod

---++ initPlugin($topic, $web, $user, $installWeb) -> $boolean
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$user= - the login name of the user
   * =$installWeb= - the name of the web the plugin is installed in

REQUIRED

Called to initialise the plugin. If everything is OK, should return
a non-zero value. On non-fatal failure, should write a message
using Foswiki::Func::writeWarning and return 0. In this case
%FAILEDPLUGINS% will indicate which plugins failed.

In the case of a catastrophic failure that will prevent the whole
installation from working safely, this handler may use 'die', which
will be trapped and reported in the browser.

You may also call =Foswiki::Func::registerTagHandler= here to register
a function to handle variables that have standard TWiki syntax - for example,
=%MYTAG{"my param" myarg="My Arg"}%. You can also override internal
TWiki variable handling functions this way, though this practice is unsupported
and highly dangerous!

__Note:__ Please align variables names with the Plugin name, e.g. if 
your Plugin is called FooBarPlugin, name variables FOOBAR and/or 
FOOBARSOMETHING. This avoids namespace issues.


=cut

sub initPlugin {
    my( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if( $Foswiki::Plugins::VERSION < 1.026 ) {
        Foswiki::Func::writeWarning( "Version mismatch between $pluginName and Plugins.pm" );
        return 0;
    }

    # Set plugin preferences in LocalSite.cfg
    $debug = $Foswiki::cfg{Plugins}{TimeCalcPlugin}{Debug} || 0;

    Foswiki::Func::registerTagHandler( 'WORKINGDAYS', \&_WORKINGDAYS );
    

    # Plugin correctly initialized
    return 1;
}

sub _WORKINGDAYS {
    my($session, $params, $theTopic, $theWeb) = @_;
    # $session  - a reference to the TWiki session object (if you don't know
    #             what this is, just ignore it)
    # $params=  - a reference to a Foswiki::Attrs object containing parameters.
    #             This can be used as a simple hash that maps parameter names
    #             to values, with _DEFAULT being the name for the default
    #             parameter.
    # $theTopic - name of the topic in the query
    # $theWeb   - name of the web in the query
    # Return: the result of processing the variable

    # For example, %EXAMPLETAG{'hamburger' sideorder="onions"}%
    # $params->{_DEFAULT} will be 'hamburger'
    # $params->{sideorder} will be 'onions'
    
    my $startdate    = defined $params->{startdate} ?
                       Foswiki::Time::parseTime( $params->{startdate} ) :
                       time();
    my $enddate      = defined $params->{enddate} ?
                       Foswiki::Time::parseTime( $params->{enddate} ) :
                       time();
    my $holidaysin   = defined $params->{holidays} ?
                       $params->{holidays} : '';
    my $includestart = defined $params->{includestart} ?
                       Foswiki::Func::isTrue( $params->{includestart} ) : 0;
    my $includeend   = defined $params->{includeend} ?
                       Foswiki::Func::isTrue( $params->{includeend} ) : 1;

    
    my %holidays = ();
    if ( $holidaysin ) {
        foreach my $holiday ( split( /\s*,\s*/, $holidaysin ) ) {
            $holidays{ Foswiki::Time::parseTime( $holiday ) } = 1;
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
    my $work_days    = $elapsed_days - ( $whole_weeks * 2 );

    for ( my $i = 0 ; $i < $extra_days ; $i++ ) {
        my $tempwday = ( gmtime( $enddate - $i * 86400 ) )[6];
        if ( $tempwday == 6 || $tempwday == 0 ) {
            $work_days--;
        }
    }
    
    foreach my $holiday ( keys %holidays ) {
        my $weekday = ( gmtime( $holiday ) )[6];
        if ( $holiday >= $startdate && $holiday <= $enddate &&
             $weekday != 6 && $weekday != 0 ) {
           $work_days--;
        }
    }

    return $work_days;

}

1;
