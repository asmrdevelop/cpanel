package Cpanel::Plugins::Promotions;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;

use Cpanel::Exception  ();
use Cpanel::LoadModule ();

=head1 MODULE

C<Cpanel::Plugins::Promotions>

=head1 DESCRIPTION

C<Cpanel::Plugins::Promotions> is a class that provides methods for managing plugin promotions

=cut

=head1 METHODS

=head2 C<new>

Returns the requested promotions object.

=head3 Arguments

=over

=item C<plugin>: The name of the plugin to get promotion information about. ie: 'koality'

=back

=head3 Example

my $promotions = Cpanel::Plugins::Promotions->new( plugin => 'koality' );

if ( $promotions->can_show_promotions() ) {
    #show promotions
}

=cut

sub new ( $self, $args = {} ) {

    die Cpanel::Exception::create( 'MissingParameter', 'Provide the “plugin” argument.' ) if !defined $args->{plugin};

    my $plugin = lc $args->{plugin};
    my $module = "Cpanel::Plugins::Promotions::$plugin";

    Cpanel::LoadModule::load_perl_module($module);

    my $obj = $module->new();
    return $obj;

}

=head2 C<can_show_promotions>

Returns whether or not the current server can show plugin upsell promotions to users.

=cut

sub can_show_promotions ($self) {
    die "can_show_promotions should be defined in a subclass.";
}

1;
