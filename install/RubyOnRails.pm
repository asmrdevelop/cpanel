package Install::RubyOnRails;

# cpanel - install/RubyOnRails.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

our $VERSION = '1.0';

=head1 DESCRIPTION

    Instal Ruby on Rails

=over 1

=item Type: software install, Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('ruby-on-rails');

    return $self;
}

sub perform {
    my $self = shift;

    require '/usr/local/cpanel/bin/ror_setup';    ##no critic qw(RequireBarewordIncludes)
    bin::ror_setup->script();

    return 1;
}

1;

__END__
