
# cpanel - Cpanel/FtpUtils/DomainChange.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::FtpUtils::DomainChange;

use strict;
use warnings;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::ConfigFiles                  ();
use Cpanel::FtpUtils::Passwd             ();
use Cpanel::Locale::Lazy 'lh';
use Cpanel::Validate::Domain ();

=head1 NAME

Cpanel::FtpUtils::DomainChange

=head1 DESCRIPTION

This is the FTP equivalent of Cpanel::WebDisk::Utils::_change_webdisk_domainname().
One key difference is that the Web Disk related code runs as the user because it's
modifying files under the user's home directory, but this FTP-related code runs as
root because it's modifying files in /etc/proftpd.

=head1 FUNCTIONS

=head2 change_domain_name(CPUSER, OLDDOMAIN, NEWDOMAIN)

Given a cPanel account CPUSER, changes all FTP accounts
at OLDDOMAIN to use NEWDOMAIN.

Important note: This does not rename the FTP home directories. If the FTP home directory
contains the name of the account (as is the default), then it will end up retaining the
old account name in the home directory. This is thought to be the lesser of two evils,
as renaming the directory could have any number of unforeseen consequences.

Returns: nothing

Throws: An exception will be thrown if the file(s) can't be updated.

=cut

sub change_domain_name {
    my ( $acct, $old_domain, $new_domain ) = @_;
    if ($>) {
        die lh()->maketext('You must run this code as the [asis,root] user.');
    }

    if ( !$acct ) {
        die lh()->maketext( 'Missing parameter: [_1]', 'CPUSER' );
    }

    Cpanel::Validate::Domain::valid_domainname_for_customer_or_die($_) for $new_domain;

    my $new_domain_owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $new_domain, { default => '' } );
    if ( !$new_domain_owner ) {
        die lh()->maketext( 'The system could not locate the owner of the domain “[_1]”.', $new_domain );
    }
    elsif ( $new_domain_owner ne $acct ) {
        die lh()->maketext( 'The cPanel account “[_1]” does not own the domain “[_2]”.', $acct, $new_domain );
    }

    my $passwd_file = _passwd_dir() . '/' . $acct;

    Cpanel::FtpUtils::Passwd::edit_passwd_file(
        $passwd_file,
        sub {
            my ($fields_ar) = @_;
            if ( $fields_ar->[0] =~ s/(@.*)\Q$old_domain\E$/$1$new_domain/ ) {
                return 1;
            }
            return 0;
        }
    );

    _ftpupdate($acct);    # sync changes to passwd.vhosts

    return;
}

sub _passwd_dir {
    my $dir = $Cpanel::ConfigFiles::FTP_PASSWD_DIR || die;
    return $dir;
}

sub _ftpupdate {
    my ($acct) = @_;
    require Cpanel::ServerTasks;
    return Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 10, "ftpupdate" );
}

1;
