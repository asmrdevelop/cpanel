package Whostmgr::Security;

# cpanel - Whostmgr/Security.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::Security - Set and get system password requirements

=head1 SYNOPSIS

    use Whostmgr::Security ();

    my $strengths_hr = Whostmgr::Security::get_min_pw_strengths();
    Whostmgr::Security::set_min_pw_strengths( 'default' => $strengths_hr->{default} + 20 );

=head1 DESCRIPTION

This module encapsulates the logic to set and get password strength requirements for cPanel & WHM.

=cut

use Cpanel::Config::CpConfGuard       ();
use Cpanel::PasswdStrength::Check     ();
use Cpanel::PasswdStrength::Constants ();
use Cpanel::Exception                 ();

my $locale;

=head1 METHODS

=head2 set_min_pw_strengths(%args)

Sets the minimum password strength requirements for the system.

=over 3

=item C<< %args >> [in, required]

A hash containing the name of the password strength setting and the value
for that setting.

See L<Cpanel::PasswdStrength::Constants> for valid names.

If a particular password strength setting is not provided, it is ignored.

If a particular password strength setting is provided but is empty, it is
deleted from the cpanel config file.

If a particular password strength setting is provided and is valid, it is
set and the cpanel config file is updated.

=back

B<Returns>: On failure, returns a list with a boolean and a message describing the failure. On success, returns 1.

=cut

sub set_min_pw_strengths {    ## no critic qw(Subroutines::RequireArgUnpacking) -- Do not want to change the interface for this legacy code
    return ( 0, _locale()->maketext('No new values were given.') ) if !@_;

    my %opts = @_;

    my $error;

    my %convert_pw_strength_to_cpconf_key = _get_pass_str_keys();

    my $cpguard   = Cpanel::Config::CpConfGuard->new();
    my $cpconf_hr = $cpguard->{'data'};

    for my $key ( keys %convert_pw_strength_to_cpconf_key ) {
        if ( exists $opts{$key} ) {
            if ( !length $opts{$key} ) {
                delete $cpconf_hr->{ $convert_pw_strength_to_cpconf_key{$key} };
            }
            else {
                my $val = Cpanel::PasswdStrength::Check::valid_strength( $opts{$key} );

                if ( !defined $val ) {
                    $error = _locale()->maketext( 'Invalid value for “[_1]”: [_2]', $key, $opts{$key} );
                }
                else {
                    $cpconf_hr->{ $convert_pw_strength_to_cpconf_key{$key} } = $val;
                }
            }

            last if $error;
        }
    }

    if ( !length $cpconf_hr->{'minpwstrength'} ) {
        $error = _locale()->maketext( 'The value for “[_1]” may not be empty or undefined.', "default" );
    }

    if ($error) {
        $cpguard->abort();    #In case Perl doesn't call DESTROY for some reason.
        return ( 0, $error );
    }
    else {
        my $success = $cpguard->save();
        if ( !$success ) {
            return ( 0, _locale()->maketext('Unable to save configuration; check system logs for details.') );
        }
    }

    # Case CPANEL-32886: cpsrvd *must* be restarted to refresh AdminBin view of %Cpanel::CONF.
    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task( ['CpServicesTasks'], "restartsrv cpsrvd" );

    return 1;
}

=head2 get_min_pw_strengths()

Gets the mininum password strength requirements for the system.

If a password strength setting is missing from the cpanel config, we set it
to the default password strength.

=over 3

=item C<< $name >> [in, optional]

When specified, retrieves just the desired password strength setting.

See L<Cpanel::PasswdStrength::Constants> for valid names.

=back

B<Returns>: A hashref consisting of password strength names and their corresponding setting.

=cut

sub get_min_pw_strengths {
    my ($name) = @_;
    my %convert_pw_strength_to_cpconf_key = _get_pass_str_keys();

    my $cpconf_hr = Cpanel::Config::CpConfGuard->new(
        'loadcpconf'  => 1,
        'no_validate' => 1
    )->config_copy;

    die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid password strength setting.', [$name] ) if ( $name && !exists $convert_pw_strength_to_cpconf_key{$name} );

    my %strengths = ();
    foreach my $key ( ($name) ? $name : keys %convert_pw_strength_to_cpconf_key ) {

        # If we cannot find the strength for a particular key, fallback to the default strength
        if ( $key && length $cpconf_hr->{ $convert_pw_strength_to_cpconf_key{$key} } ) {
            $strengths{$key} = $cpconf_hr->{ $convert_pw_strength_to_cpconf_key{$key} };
        }
        else {
            $strengths{$key} = $cpconf_hr->{'minpwstrength'} // 0;
        }
    }

    return \%strengths;
}

sub _get_pass_str_keys {
    return (
        default => 'minpwstrength',
        (
            map { $_ => "minpwstrength_$_" }
              keys %Cpanel::PasswdStrength::Constants::APPNAMES
        ),
    );
}

sub _locale {
    require Cpanel::Locale;
    return ( $locale ||= Cpanel::Locale->get_handle() );
}

1;
