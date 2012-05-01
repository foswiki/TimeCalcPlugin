#!/usr/bin/perl -w
#
# Build class for TimeCalcPlugin
#
BEGIN {
    unshift @INC, split( /:/, $ENV{FOSWIKI_LIBS} );
}

use Foswiki::Contrib::Build;

# Create the build object
$build = new Foswiki::Contrib::Build('TimeCalcPlugin');

# Build the target on the command line, or the default target
$build->build( $build->{target} );

