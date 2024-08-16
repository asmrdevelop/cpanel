package Cpanel::Debug::Hooks;

# cpanel - Cpanel/Debug/Hooks.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Debug            ();
use Cpanel::FileUtils::Write ();

my %LOG_LEVEL = (

    #disabled
    0 => 0,

    #Log information about defined hooks as they are executed. Do not include data.
    log => 1,

    #Log information about defined hooks as they are executed and their respective data.
    logdata => 2,

    #IMPORTANT: This setting can output a large amount of data.
    #This data is potentially log-sensitive. You should be careful when using this debug value.
    #Log information about every hookable event that is traversed, even if there are no defined hooks for the hookable event. This output includes details for defined hooks with data, i.e., the same as “logdata”.
    logall => 3,
);

my %LEVEL_LOG = reverse %LOG_LEVEL;

#Returns a string (possibly “0”).
sub get_current_value {
    my $file_length = ( stat($Cpanel::Debug::HOOKS_DEBUG_FILE) )[7] || 0;

    my $level = $LEVEL_LOG{$file_length};
    if ( !defined $level ) {
        warn "Unrecognized hooks debug file ($Cpanel::Debug::HOOKS_DEBUG_FILE) length: $file_length! Defaulting to disabled …";
        $level = 0;
    }

    return $level;
}

#Accepts a string (possibly “0”).
sub set_value {
    my ($new_value) = @_;

    my $number = $LOG_LEVEL{$new_value};

    if ( !defined $number ) {
        my @valids = sort keys %LOG_LEVEL;
        die "Invalid hooks debug key value: “$new_value”! (Valid values are: @valids)";
    }

    #So we can tell the log level just by stat()ing the file.
    my $contents = $number x $number;

    return Cpanel::FileUtils::Write::overwrite( $Cpanel::Debug::HOOKS_DEBUG_FILE, $contents, 0644 );
}

1;
