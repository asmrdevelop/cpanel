package Install::SELinuxSetup;

# cpanel - install/SELinuxSetup.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use base qw( Cpanel::Task );

use IO::Handle ();

use Cpanel::OS               ();
use Cpanel::SafeFile         ();
use Cpanel::Debug            ();
use Cpanel::FileUtils::Write ();

=head1 DESCRIPTION

    Disable SELinux for current 'boot session' and next reboot.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

our $VERSION = '1.0';

our $SELINUX_FILE = q[/etc/selinux/config];

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('selinuxsetup');

    return $self;
}

sub perform ($self) {

    return 1 if Cpanel::OS::security_service() ne 'selinux';

    if ( -x '/usr/sbin/setenforce' ) {
        print qq[Set SELinux to permissive\n];
        system(qw{/usr/sbin/setenforce 0});
    }

    update_selinux_config();

    return 1;
}

sub update_selinux_config() {

    return unless -e $SELINUX_FILE;

    print qq[Set SELinux to permissive for next reboot\n];

    my $fh       = IO::Handle->new;
    my $filelock = Cpanel::SafeFile::safeopen( $fh, "+<", $SELINUX_FILE );
    if ( !$filelock ) {
        Cpanel::Debug::log_warn("Could not edit $SELINUX_FILE");
        return;
    }

    my $need_update;
    my @lines;
    foreach my $line ( readline $fh ) {
        if ( $line =~ qr{^\s*SELINUX\s*=\s*enforcing}i ) {
            $line        = "SELINUX=permissive\n";    # replace line
            $need_update = 1;
        }
    }
    continue {
        push @lines, $line;
    }

    if ($need_update) {
        my $content = join '', @lines;
        Cpanel::FileUtils::Write::write_fh( $fh, $content );
    }

    Cpanel::SafeFile::safeclose( $fh, $filelock );

    return $need_update;    # for unit test purpose
}

1;
