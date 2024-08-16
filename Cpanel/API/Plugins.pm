package Cpanel::API::Plugins;

# cpanel - Cpanel/API/Plugins.pm                   Copyright 2024 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Imports;

use Cpanel::Plugins::UUID       ();
use Cpanel::Validate::Boolean   ();
use Cpanel::Plugins::Promotions ();

our %API = (
    get_uuid   => { allow_demo => 0 },
    reset_uuid => { allow_demo => 0 },
);

=head1 MODULE

C<Cpanel::API::Plugins>

=head1 DESCRIPTION

C<Cpanel::API::Plugins> provides methods to interface with the common plugin framework.

=head1 FUNCTIONS

=head2 get_uuid()

Get the user's plugin UUID.

=head3 ARGUMENTS

=over

None.

=back

=head3 RETURNS

The cPanel user's UUID shared across plugins.

=over

=item uuid - string

=back

=head3 EXAMPLES

CLI ( Arguments must be uri escaped ):

uapi --user=cpanel_user Plugins get_uuid

TT:

 [%
     SET result = execute( 'Plugins', 'get_uuid', );
     SET uuid = result.data.uuid;
 %]

=cut

sub get_uuid ( $args, $result ) {

    my $uuid = Cpanel::Plugins::UUID->new();
    $result->data( { uuid => $uuid->uuid } );

    return 1;
}

=head2 reset_uuid()

Reset the user's plugin UUID and optionally generate and return a new one.

=head3 ARGUMENTS

=over

None.

=back

=head3 RETURNS

The cPanel user's UUID shared across plugins.

=over

=item uuid - string

=back

=head3 EXAMPLES

CLI ( Arguments must be uri escaped ):

uapi --user=cpanel_user Plugins reset_uuid

TT:

 [%
     SET result = execute( 'Plugins', 'reset_uuid', );
     SET uuid = result.data.uuid;
 %]

=cut

sub reset_uuid ( $args, $result ) {

    my $uuid = Cpanel::Plugins::UUID->new();
    $result->data( { uuid => $uuid->reset() } );

    return 1;
}

=head2 can_show_promotions()

Determines if the server can show promotions for specific plugins.

=head3 ARGUMENTS

=over

C<plugin> -- String. The plugin we want to query.

=back

=head3 RETURNS

Whether or not this server can show promotions for a plugin.

=over

=item can_show_promotions - bool

=back

=cut

sub can_show_promotions ( $args, $result ) {

    my $plugin = $args->get_length_required('plugin');

    my $promotions = eval { Cpanel::Plugins::Promotions->new( { plugin => $plugin } ) };
    my $err        = $@ && $@->isa('Cpanel::Exception') ? $@->get_string() : $@;

    if ($err) {
        $result->error($err);
        $result->message("Could not load methods for plugin $plugin. Check $plugin for validity.");
        return;
    }

    $result->data( { can_show_promotions => $promotions->can_show_promotions() } );

    return 1;
}

1;
