package Cpanel::TailWatch::Utils::EnableDisable;

# cpanel - Cpanel/TailWatch/Utils/EnableDisable.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# /usr/local/cpanel already in @INC
# this works but we want lowest memory possible
# use strict;

our $VERSION = 0.3;

sub Cpanel::TailWatch::enable_disable_drivers {
    my ($tw) = @_;

    # this way saves a grep each time and cuts out duplicates
    my %enable  = map { $_ => 1 } $tw->{'global_share'}{'objects'}{'param_obj'}->param('enable');
    my %disable = map { $_ => 1 } $tw->{'global_share'}{'objects'}{'param_obj'}->param('disable');
    my $verbose = $tw->{'global_share'}{'objects'}{'param_obj'}->param('verbose') ? 1 : 0;
    my $quiet   = $verbose                                                        ? 0 : 1;
    my $changed = 0;

    foreach my $module ( keys %enable ) {    # need to load modules that are not enabled
        ( $tw->_load_module( ( split( m/::/, $module ) )[-1] ) )[0] || die "Failed to load $module: $!";
    }
    foreach my $module ( keys %disable ) {    # and disabled jic
        ( $tw->_load_module( ( split( m/::/, $module ) )[-1] ) )[0] || die "Failed to load $module: $!";
    }

    for my $driver ( @{ $tw->{'enabled_modules'} } ) {
        if ( exists $enable{ $driver->[0] } ) {
            delete $enable{ $driver->[0] };
            delete $disable{ $driver->[0] };

            # enable it if needed/possible
            if ( $driver->[1] ) {

                # its already on
                $tw->log_and_say("$driver->[0] is already enabled");
            }
            else {
                if ( my $cr = $driver->[0]->can('enable') ) {

                    # call init to load modules
                    if ( my $init_cr = $driver->[0]->can('init') ) { $init_cr->(); }
                    my $object = $driver->[0]->new($tw) || $driver->[0];    # if its got enable then we can probably assume its got new()

                    # enable it
                    if ( $cr->( $tw, $object ) ) {
                        $changed++;

                        # enabled ok
                        $tw->log_and_say_if_verbose("$driver->[0] was successfully enabled");
                    }
                    else {

                        # enable failed
                        $tw->log_and_say("$driver->[0] could not be enabled");
                    }
                }
                else {

                    # does not have an enable method
                    $tw->log_and_say("$driver->[0] does not have an enable() method");
                }
            }
        }
        elsif ( exists $disable{ $driver->[0] } ) {

            # we'd never get here if it existed in %enable so no need to delete it
            # delete $enable{ $driver->[0] };
            delete $disable{ $driver->[0] };

            # Always attempt to disable the module to prevent it from showing up
            # in the interface.
            if ( my $cr = $driver->[0]->can('disable') ) {

                # call init to load modules
                if ( my $init_cr = $driver->[0]->can('init') ) { $init_cr->(); }
                my $object = $driver->[0]->new($tw) || $driver->[0];    # if its got disable then we can probably assume its got new()

                # disable it
                if ( $cr->( $tw, $object ) ) {
                    $changed++;

                    # disabled ok
                    $tw->log_and_say_if_verbose("$driver->[0] was successfully disabled");
                }
                else {

                    # disable failed
                    $tw->log_and_say("$driver->[0] could not be disabled");
                }
            }
            else {

                # does not have an disable method
                $tw->log_and_say("$driver->[0] does not have an disable() method");
            }
        }
        else {

            # not specified either way, leave it alone but log/say
            $tw->log_and_say("$driver->[0] not specified in --enable or --disable, ignoring");
        }

    }

    # log/say of any remaining (IE 'unknown' drivers in %enable or %disable)
    for my $odd_e ( sort keys %enable ) {
        $tw->log_and_say("Unknown driver '$odd_e' passed via --enable, ignoring");
    }
    for my $odd_d ( sort keys %disable ) {
        $tw->log_and_say("Unknown driver '$odd_d' passed via --disable, ignoring");
    }

    # use variables with descriptive names
    my @restart_flag_values  = $tw->{'global_share'}{'objects'}{'param_obj'}->param('restart');
    my $restart_flag_passed  = @restart_flag_values                                            ? 1 : 0;
    my $restart_flag_boolean = $tw->{'global_share'}{'objects'}{'param_obj'}->param('restart') ? 1 : 0;

    if ( $changed || $restart_flag_boolean ) {
        if ( $restart_flag_passed && !$restart_flag_boolean ) {

            # skipping restart as per flag
            $tw->log_and_say_if_verbose("Skipping restart as per given arguments");
        }
        else {

            # restarting...
            $tw->log_and_say_if_verbose("Restarting...");
            exec("$0 --restart");    # see case 11710
        }
    }
    else {

        # log/say that no restart needed since no changes...
        $tw->log_and_say_if_verbose("Skipping restart since no changes resulted from arguments");
    }
}

1;
