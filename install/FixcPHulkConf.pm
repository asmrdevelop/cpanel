package Install::FixcPHulkConf;    ## no critic(RequireFilenameMatchesPackage)

# cpanel - install/FixcPHulkConf.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

use Cpanel::Config::Hulk::Conf ();
use Cpanel::Config::Hulk::Load ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Adjust cpanel.config file mark_as_brute value
    to use the same value as max_failures_byip,
    and notify customer on updates.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('fix_cphulk_config');

    # Cpanel::Config::Hulk::Conf can queue tasks.
    $self->add_dependencies(qw( taskqueue ));

    return $self;
}

sub perform {
    my $self = shift;

    my $cphulk_conf = Cpanel::Config::Hulk::Load::loadcphulkconf();
    if ( $cphulk_conf->{'mark_as_brute'} < $cphulk_conf->{'max_failures_byip'} ) {
        $cphulk_conf->{'mark_as_brute'} = $cphulk_conf->{'max_failures_byip'};
        Cpanel::Config::Hulk::Conf::savecphulkconf($cphulk_conf);
        $self->notify();
    }

    return 1;
}

sub notify {
    my ($self) = @_;
    require Cpanel::Notify;
    return Cpanel::Notify::notification_class(
        'class'            => 'Install::FixcPHulkConf',
        'application'      => 'Install::FixcPHulkConf',
        'constructor_args' => [
            origin => 'install',
        ]
    );
}

1;
