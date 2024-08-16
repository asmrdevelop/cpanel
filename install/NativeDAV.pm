package Install::NativeDAV;

# cpanel - install/NativeDAV.pm                    Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent                  qw( Cpanel::Task );
use Cpanel::SafeRun::Simple ();

use Cpanel::Server::Type::Role::CalendarContact ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    This is responsible for getting a system ready to use the new Native DAV support via cpdavd for Calendars and Contacts
    - Migrates existing CCS accounts over to new Native DAV support in cpdavd

=over 1

=item Type: Fresh Install, Sanity, cPanel setup

=item Frequency: once

=item EOL: 11.128

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new ($class) {

    my $self = $class->SUPER::new();

    $self->set_internal_name('nativedav');
    $self->enable_only_perform_once();

    return $self;
}

sub perform ($self) {

    return unless Cpanel::Server::Type::Role::CalendarContact->is_enabled();

    # Only run the migration if we appear to have CCS installed
    return 1 if !-f '/var/cpanel/ccs/ccs-persistance.json';

    # Migrate CCS to native cpdavd
    my $out = Cpanel::SafeRun::Simple::saferun('/usr/local/cpanel/scripts/migrate_ccs_to_cpdavd');
    print $out if defined $out;

    # Disable CCS
    Cpanel::SafeRun::Simple::saferun( '/usr/bin/systemctl', 'disable', 'cpanel-ccs' );
    Cpanel::SafeRun::Simple::saferun( '/usr/bin/systemctl', 'stop',    'cpanel-ccs' );

    # Restart cpdavd to take over port 2080
    Cpanel::SafeRun::Simple::saferun( '/usr/local/cpanel/scripts/restartsrv_cpdavd', '--hard' );

    # While it may seem redundant to disable CCS first then uninstall
    # (as uninstall also would disable it), this ensures a minimum amount of
    # time where something is not sitting on port 2079/2080.
    require Cpanel::Plugins;
    Cpanel::Plugins::uninstall_plugins('cpanel-ccs-calendarserver');

    return 1;
}

1;

__END__
