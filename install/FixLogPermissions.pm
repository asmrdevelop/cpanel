package Install::FixLogPermissions;

# cpanel - install/FixLogPermissions.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

use Cpanel::SafeFind         ();
use Cpanel::FileUtils::Chown ();
use Cpanel::Sys::Chattr      ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Adjust owner and permissions of cpanel log files.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

# List of directories, and logs within them to reset permissions on.
# Directories should *not* have an ending '/'.
# Logs can be a regex.

my %logs = (
    '/usr/local/cpanel/logs' => [
        qw {
          addbandwidth\.log
          build_locale_databases_log
          cpbackup_transporter\.log
          cphulkd\.log
          cphulkd_errors\.log
          cpwrapd_log
          dnsadmin_log
          dnsadmin_softlayer_log
          license_log
          queueprocd\.log
          roundcube_sqlite_convert_log
          safeapacherestart_log
          setupdbmap_log
          splitlogs_log
          tailwatchd_log
        }
    ],
    '/var/cpanel/logs' => [
        qw {
          cpaddonsup\.[0-9]+\.txt
          cpusers-autofixer\.[0-9]+
          imap_conversion\.log
          imap_conversion_failures
          mysql_upgrade\.log\.[0-9]+-[0-9]+
          restore_account_plans\.[0-9]+
          restore_account_plans_report\.[0-9]+
          setupmailserver
          setupnameserver
        }
    ],
    '/var/log' => [
        qw {
          chkservd\.log
          quota_enable\.log
        }
    ],
    '/var/cpanel/maildirconvert' => [
        qw {
          log\.[\-_a-z]+
        }
    ],
    '/var/cpanel/updatelogs' => [
        qw {
          taskrun-[0-9]+\.log
          update\.[0-9]+\.log
          summary\.log
          maildirconversion\.[0-9]+
        }
    ],
    '/etc/apache2/logs/domlogs' => [
        qw {
          proxy-subdomains-vhost\.localhost
        }
    ],
);

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('fixlogpermissions');

    return $self;
}

sub perform {
    my $self = shift;

    foreach my $dir ( sort keys %logs ) {
        next unless -d $dir;
        my $logs_re = '/(?:' . ( join "|", map { "(?:$_)" } @{ $logs{$dir} } ) . ')';
        Cpanel::SafeFind::find(
            {
                wanted => sub {

                    # We don't really need to recurse into sub-directories (yet).
                    if ( -d && ( $File::Find::name ne $dir ) ) {
                        $File::Find::prune = 1;
                        return;
                    }

                    # Match logs, and change permissions if necessary.
                    if ( $File::Find::name =~ /$logs_re/ ) {

                        open( my $fh, ">>", $File::Find::name ) or return;
                        my $append_only = Cpanel::Sys::Chattr::get_attribute( $fh, 'APPEND' );

                        if ($append_only) {
                            Cpanel::Sys::Chattr::remove_attribute( $fh, 'APPEND' );
                        }

                        Cpanel::FileUtils::Chown::check_and_fix_owner_and_permissions_for(
                            'uid'         => 0,
                            'gid'         => 0,
                            'octal_perms' => 0600,
                            'path'        => $File::Find::name,
                            'create'      => 0,
                        );

                        if ($append_only) {
                            Cpanel::Sys::Chattr::set_attribute( $fh, 'APPEND' );
                        }
                        close($fh);
                    }
                },
            },
            $dir
        );
    }

    return 1;
}

1;

__END__
