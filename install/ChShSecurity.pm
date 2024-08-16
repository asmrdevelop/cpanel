package Install::ChShSecurity;

# cpanel - install/ChShSecurity.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

our $VERSION = '1.0';

=head1 DESCRIPTION

    Adjust /usr/bin/chsh permission

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

    $self->set_internal_name('chshsecurity');

    return $self;
}

sub perform {
    my $self     = shift;
    my $filename = '/usr/bin/chsh';

    if ( -e $filename ) {
        chmod 0711, $filename;
    }

    return 1;
}

1;

__END__
