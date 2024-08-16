package Install::CheckRemoteMySQLVersion;

# cpanel - install/CheckRemoteMySQLVersion.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::MysqlUtils::Version ();

use base qw( Cpanel::Task );

=head1 DESCRIPTION

    Check and notify user when using remote MySQL < 5.6

=over 1

=item Type: Sanity

=item Frequency: Always

=item EOL: never

=back

=cut

our $VERSION = '1.0';

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('check_remote_mysql_version');

    return $self;
}

sub perform {
    my $self = shift;

    eval {
        my $version = Cpanel::MysqlUtils::Version::current_mysql_version();
        $self->notify( $version->{'short'} ) if ( $version->{'is_remote'} && $version->{'short'} < 5.6 );
    };

    return 1;
}

sub notify {
    my ( $self, $current_version ) = @_;

    require Cpanel::Notify;
    return Cpanel::Notify::notification_class(
        'class'            => 'Install::CheckRemoteMySQLVersion',
        'application'      => 'Install::CheckRemoteMySQLVersion',
        'constructor_args' => [
            'origin'          => 'check_remote_mysql_version',
            'current_version' => $current_version,
        ]
    );
}

1;
