
# cpanel - Cpanel/cPAddons/Security.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Security;

use strict;
use warnings;

use Cpanel::cPAddons::File::Perms ();
use Cpanel::Imports;

=head1 NAME

Cpanel::cPAddons::Security

=head1 DESCRIPTION

Utility module where Security Policies are implemented.

=head1 METHODS

=head2 Cpanel::cPAddons::Security::process_config_file_permissions()

Process the process_config_file_permissions security policies based on the metadata provided by a specific cpaddon.

This policy will set the listed files to 0600 if mod_suexec, mod_suphp, mod_ruid2, or mpm_itk are installed and to 0644 otherwise.

=head3 ARGUMENTS

=over

=item policy

- hash ref - Containing the following properties.

=over

=item policy.description

string - optional output description for verbose mode.

=back

=over

=item policy.fix

boolean - true means fix the permissions, false means just warn about it.

=back

=over

=item policy.files

array ref - list of files to adjust

=back

=back

=head3 RETURNS

boolean - true for success, false otherwise.

=head3 SIDE EFFECTS

As with all policies, it reports success and failure via message in the session object.

Check in the session->{security_policies} and/or the notices collection.

=cut

sub process_config_file_permissions {
    my ( $policy, $session ) = @_;

    my $name         = $policy->{name};
    my $runs_as_user = Cpanel::cPAddons::File::Perms::runs_as_user();
    if ( $policy->{fix} ) {
        my @files = map { "$session->{installdir}/$_" } @{ $policy->{files} || [] };

        if ( !@files ) {
            $session->add_critical_error( locale()->maketext('The [asis, cPAddon’s] metadata requested that the system secure specific files if the script runs as the script owner, but the file list is empty or missing.') );
            $session->{security_policies}{$name} = 'error';
            return 0;
        }

        my ( $ret, $msg ) = Cpanel::cPAddons::File::Perms::fix( \@files, $runs_as_user ? 0600 : 0644 );
        if ($ret) {
            $session->add_error($msg);
            $session->{security_policies}{$name} = 'error';
        }
    }

    if ( !$runs_as_user ) {
        $session->add_warning(
            locale()->maketext('The web server does not run scripts as the script owner. The system must set the file permission on this application more permissively. This can result in security issues with this application on shared servers.'),
            id => 'web-server-not-running-as-owner-warning',
        );
        $session->{security_policies}{$name} = 'warn';
    }

    return 1;
}

=head2 Cpanel::cPAddons::Security::process_file_permissions()

Process the process_file_permissions security policies based on the meta-data provided by a specific cpaddon.

This policy will set the listed files and folders to the value in perms.as_user if mod_suphp, mod_ruid2, or mpm_itk are installed. Otherwise the value in perms.as_nobody will be used as the permission.

=head3 ARGUMENTS

=over

=item policy

- hash ref - Containing the following properties.

=over

=item policy.description

string - optional output description for verbose mode.

=back

=over

=item policy.fix

boolean - true means fix the permissions, false means just warn about it.

=back

=over

=item policy.files

array ref - list of files to adjust

=back

=over

=item policy.perms

hash ref - with the following options

=over

=item as_user - string

Linux permissions to use when running as the script owner.

=item as_nobody - string

Linux permissions to use when running as a fixed user.

=back

=back

=back

=head3 RETURNS

boolean - true for success, false otherwise.

=head3 SIDE EFFECTS

As with all policies, it reports success and failure via message in the session object.

Check in the session->{security_policies} and/or the notices collection.

=cut

sub process_file_permissions {
    my ( $policy, $session ) = @_;

    my $name         = $policy->{name};
    my $runs_as_user = Cpanel::cPAddons::File::Perms::runs_as_user();
    if ( $policy->{fix} ) {
        my @files = map { "$session->{installdir}/$_" } @{ $policy->{files} || [] };

        if ( !@files ) {
            $session->add_critical_error( locale()->maketext('The [asis, cPAddon’s] metadata requested that the system secure specific files if the script runs as the script owner, but the file list is empty or missing.') );
            $session->{security_policies}{$name} = 'error';
            return 0;
        }

        my $perms = $policy->{perms};
        if ( !$perms || ref $perms ne 'HASH' || !keys %$perms ) {
            $session->add_critical_error( locale()->maketext( 'The [asis,cPAddon’s] metadata requested that the system secure specific files if the script runs as the script owner, but the [asis,cPAddon] developer did not provide the [asis,perms] [asis,hash] in the policy. See the following example: [_1]', _get_example() ) );
            $session->{security_policies}{$name} = 'error';
            return 0;
        }

        if ($runs_as_user) {
            if ( !defined $perms->{as_user} ) {
                $session->add_critical_error( locale()->maketext('The [asis, cPAddon’s] metadata requested that the system secure specific files and directories when the script runs as the script owner, but the [asis,perms] [asis,hash] does not contain the “[asis,as_user]” [asis,key-value] pair.') );
                $session->{security_policies}{$name} = 'error';
            }
            else {
                my ( $ret, $msg ) = Cpanel::cPAddons::File::Perms::fix( \@files, $perms->{as_user} );
                if ($ret) {
                    $session->add_error($msg);
                    $session->{security_policies}{$name} = 'error';
                }
            }
        }
        else {
            if ( !defined $perms->{as_nobody} ) {
                $session->add_critical_error( locale()->maketext('The [asis, cPAddon’s] metadata requested that the system adjust specific file and directory permissions when the script runs as the [asis,nobody] user, but the [asis,perms] [asis,hash] does not contain the “[asis,as_nobody]” [asis,key-value] pair.') );
                $session->{security_policies}{$name} = 'error';
            }
            else {
                my ( $ret, $msg ) = Cpanel::cPAddons::File::Perms::fix( \@files, $perms->{as_nobody} );
                if ($ret) {
                    $session->add_error($msg);
                    $session->{security_policies}{$name} = 'error';
                }
            }
        }
    }

    if ( !$runs_as_user ) {
        $session->add_warning(
            locale()->maketext('The web server does not run scripts as the script owner. The system must set the file permission on this application more permissively. This can result in security issues with this application on shared servers.'),
            id => 'web-server-not-running-as-owner-warning',
        );
        $session->{security_policies}{$name} = 'warn';
    }

    return 1;
}

sub _get_example {
    return << "EXAMPLE";
{
    name        => 'process_file_permissions',
    description => 'Description to output to ui',
    fix         => 1,
    files       => [  'folder1' ],
    perms => {
        as_user   => '700',
        as_nobody => '744',
    }
}
EXAMPLE
}
1;
