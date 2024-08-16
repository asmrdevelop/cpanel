package Install::DefaultFeatureFlags;

# cpanel - install/DefaultFeatureFlags.pm          Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw( Cpanel::Task );

use Cpanel::FeatureFlags          ();
use Cpanel::FeatureFlags::Migrate ();

our $VERSION = '1.0';

=head1 DESCRIPTION

Create feature flags directory and populate it from the add.cfg and remove.cfg files shipped with the product.

Also:

* Migrates legacy experimental flags from /var/cpanel/experimental to this system.

=over

=item Type: Fresh Install

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my ($class) = @_;
    my $self = $class->SUPER::new();

    $self->set_internal_name('default_feature_flags');

    return $self;
}

sub perform {
    my $self = shift;
    Cpanel::FeatureFlags::install( force => 1 );
    Cpanel::FeatureFlags::Migrate::migrate_experimental_system();
    return 1;
}

1;
