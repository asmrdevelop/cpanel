package Install::FastMail;

# cpanel - install/FastMail.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;
use Cpanel::Init::Simple ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Update, enable and start fastmail service

=over 1

=item Type: Fresh Install, Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('fastmail');

    return $self;
}

sub perform {
    my $self = shift;

    Cpanel::Init::Simple::call_cpservice_with( 'fastmail' => qw/install enable/ );

    require '/usr/local/cpanel/scripts/fastmail';    ##no critic qw(RequireBarewordIncludes)
    scripts::fastmail->script();
    return 1;
}

1;

__END__
