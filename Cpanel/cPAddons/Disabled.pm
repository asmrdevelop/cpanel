
# cpanel - Cpanel/cPAddons/Disabled.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Disabled;

use strict;
use warnings;
use Cpanel::cPAddons::Cache ();

our $DISABLED_FILE = '/var/cpanel/cpaddons_disabled';

=head1 NAME

Cpanel::cPAddons::Disabled

=head1 DESCRIPTION

Used for checking whether certain operations for an addon have been disabled via the
global disabled file at /var/cpanel/cpaddons_disabled.

B<Note>: There are three ways of disabling items:
it):

1. The global disable file, which is interpreted by this module.

2. Feature lists, which are handled by B<Cpanel::cPAddons::Class>.

3. Completely uninstalling it via WHM.

=head1 FUNCTIONS

=head2 check_if_action_is_disabled(ACTION, MOD)

Checks whether the specified action is disabled for the specifeid module.

=head3 Arguments

- ACTION - String - The three actions that are individually manageable are 'install', 'uninstall', and 'upgrade'.
Any other actions will either be all enabled or all disabled.

- MOD - String - The cPAddons module name. See the MODULE NAMES section of B<perldoc Cpanel::cPAddons::Module> for more info.

=head3 Returns

True if the specified action is disabled for the module in question. False otherwise.

=cut

sub check_if_action_is_disabled {
    my ( $action, $mod ) = @_;

    return if ( !$action || !$mod );

    my %disabled = manage_disablement($mod);

    if ( $action eq 'install' ) {
        return $disabled{'1'} if $disabled{'1'};
    }
    elsif ( $action eq 'upgrade' ) {
        return $disabled{'2'} if $disabled{'2'};
    }
    elsif ( $action eq 'uninstall' ) {
        return $disabled{'3'} if $disabled{'3'};
    }
    else {
        return $disabled{'4'} if $disabled{'4'};
    }

    return;
}

=head2 manage_disablement(MOD)

Sets up the on-disk and in-memory caches of disabled modules.

=head3 Arguments

- MOD - String - The cPAddons module name. See the MODULE NAMES section of B<perldoc Cpanel::cPAddons::Module> for more info.

=head3 Returns

List of key/value pairs for a hash to form the disabled list. (Used by check_if_action_is_disabled.)

=head3 Side effects

Updates on-disk cache of disabled modules.

=cut

sub manage_disablement {
    my ($mod)        = @_;
    my %tmp_disabled = ( 1 => '', 2 => '', 3 => '', 4 => '' );
    my $alldis_hr    = {};
    if ( Cpanel::cPAddons::Cache::read_cache( $DISABLED_FILE, $alldis_hr ) ) {
        if ( exists $alldis_hr->{$mod} ) {
            if ( $alldis_hr->{$mod}->{'typ'} eq 'time' ) {

                _enable_or_disable_module(
                    checker      => sub { time() > $alldis_hr->{$mod}->{'tyv'} },
                    alldis_hr    => $alldis_hr,
                    mod          => $mod,
                    tmp_disabled => \%tmp_disabled,
                );

            }
            elsif ( $alldis_hr->{$mod}->{'typ'} eq 'mver' ) {

                _enable_or_disable_module(
                    checker      => sub { _module_version_is_ok( $alldis_hr, $mod ) },
                    alldis_hr    => $alldis_hr,
                    mod          => $mod,
                    tmp_disabled => \%tmp_disabled,
                );

            }
            elsif ( $alldis_hr->{$mod}->{'typ'} eq 'sver' ) {

                _enable_or_disable_module(
                    checker      => sub { _software_version_is_ok( $alldis_hr, $mod ) },
                    alldis_hr    => $alldis_hr,
                    mod          => $mod,
                    tmp_disabled => \%tmp_disabled,
                );

            }
            else {
                _disable_module(
                    alldis_hr    => $alldis_hr,
                    mod          => $mod,
                    tmp_disabled => \%tmp_disabled,
                );
            }
        }
    }
    return %tmp_disabled;
}

sub _enable_or_disable_module {
    my %args = @_;
    my ( $checker, $alldis_hr, $mod, $tmp_disabled ) = delete @args{qw(checker alldis_hr mod tmp_disabled)};

    if ( $checker->() ) {
        _enable_module( $alldis_hr, $mod );
    }
    else {
        _disable_module( $alldis_hr, $mod, $tmp_disabled );
    }
    return;
}

sub _enable_module {
    my ( $alldis_hr, $mod ) = @_;
    delete $alldis_hr->{$mod};
    if ( !Cpanel::cPAddons::Cache::write_cache( $DISABLED_FILE, $alldis_hr ) ) {
        return 0;
    }
    return 1;
}

sub _disable_module {
    my ( $alldis_hr, $mod, $tmp_disabled ) = @_;
    for ( split /,/, $alldis_hr->{$mod}->{'dis'} ) {
        $tmp_disabled->{$_} = $alldis_hr->{$mod}->{'msg'};
    }
    return;
}

1;
