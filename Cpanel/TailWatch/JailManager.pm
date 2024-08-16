package Cpanel::TailWatch::JailManager;

# cpanel - Cpanel/TailWatch/JailManager.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::TailWatch::JailManager::Config ();

##############################################################
## no other use()s, require() only *and* only then in init() #
##############################################################

our $VERSION = 0.4;

sub init {

    # this is where modules should be require()'d
    # this method gets called if PKG->is_enabled()
    return 1;
}

*is_enabled = \&Cpanel::TailWatch::JailManager::Config::is_enabled;

#
# No enable / disable method as jailapache in cpanel.config decides this
#

sub new {
    my ( $my_ns, $tailwatch_obj ) = @_;
    my $self = bless { 'tailwatch_obj' => $tailwatch_obj, 'internal_store' => { 'check_interval' => 1800, 'number_of_runs' => 0, 'last_check_time' => 0 } }, $my_ns;

    #$tailwatch_obj->register_module( $self, __PACKAGE__ );

    $self->{'tailwatch_obj'}->log("Registered Module");
    $tailwatch_obj->register_action_module( $self, __PACKAGE__ );

    return $self;
}

sub run {
    my ( $my_ns, $tailwatch_obj, $time ) = @_;

    # Status of true means we are inside a service check but we have passed control back to the main tailwatch
    # process so other drivers can be handled.  If we are here then we need to continue service checks.
    if (   ( $time - $my_ns->{'internal_store'}->{'last_check_time'} ) > $my_ns->{'internal_store'}->{'check_interval'}
        || ( $time + $my_ns->{'internal_store'}->{'last_check_time'} ) < $my_ns->{'internal_store'}->{'check_interval'} ) {    #Now accounts to time warps

        if ( $my_ns->{'internal_store'}->{'child_pid'}
            && kill( 0, $my_ns->{'internal_store'}->{'child_pid'} ) == 1 ) {

            $my_ns->{'tailwatch_obj'}->log("Previous JailManager update still running");

            return;
        }

        $my_ns->{'internal_store'}->{'last_check_time'} = $my_ns->{'internal_store'}->{'child_start_time'} = $time;

        #needs to run in a child to prevent recentauthedmailiptracker waiting
        if ( $my_ns->{'internal_store'}->{'child_pid'} = fork() ) {
            $my_ns->{'tailwatch_obj'}->log("Updating jails");
        }
        else {
            local $0 = $0 . " - jailmanager";
            require Cpanel::JailManager;
            Cpanel::JailManager->new( 'log_func' => sub { $my_ns->{'tailwatch_obj'}->log(@_); } )->update();
            $my_ns->{'tailwatch_obj'}->log("Finished updating jails");
            exit(0);
        }

    }

    return 1;
}
## Driver specific helpers ##

1;
