package Cpanel::API::NVData;

# cpanel - Cpanel/API/NVData.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Logger::Soft ();
use Cpanel::NVData       ();

=head1 MODULE

B<Cpanel::API::NVData>

=head1 DESCRIPTION

C<Cpanel::API::NVData> provides remote api access to the name/value data
pairs for each user. These pairs are stored in files for each user in:

  /home/<user>/.cpanel/nvdata/<name>

For webmail users the filename is prepended as follows:

  /home/<user>/.cpanel/nvdata/<webmail_user>_<name>

This data is intended to store personalization information for various
UI and core components.

It's not recommended to store security related data in this data store.

=cut

sub _get {
    my ( $names, $default ) = @_;
    my $appname = $Cpanel::appname // '';
    return [
        map {
            {
                'name'  => $_,
                'value' => (
                    Cpanel::NVData::_get(
                          $appname eq 'webmail'
                        ? $Cpanel::authuser . '_' . $_
                        : $_
                    ) // $default
                ),
            }
          }
          split( /\|/, $names )
    ];
}

=head1 FUNCTIONS

=head2 get(names => 'name1|name2...', default => '')

Fetches the list of names from the key/value store.

=head3 DEPRECATED

Use C<Cpanel::API::Personalization::get> as a replacement.

=head3 ARGUMENTS

=over

=item names

String - Pipe (|) delimited list of name/value pairs to retrieve

=item default

Optional - String - Default value to return if the name has not been set.

=back

=head3 RETURNS

Array Ref of Hash Refs where each Hash Ref has the following properties:

=over

=item name

String - name associated with the pair.

=item value

String - value of the item

=back

=cut

sub get {
    my ( $args, $result ) = @_;

    Cpanel::Logger::Soft::deprecated('The [asis,NVData::get] method is deprecated. Please use [asis,Personalization::get] instead.');

    $result->data( _get( $args->get("names"), $args->get("default") ) );

    return 1;
}

=head2 set(names => 'name1|name2|...', ...)

Sets name/value pairs.

=head3 DEPRECATED

Use C<Cpanel::API::Personalization::set> as a replacement.

=head3 ARGUMENTS

=over

=item names

String - Pipe (|) delimited list of name/value pairs to retrieve

=item <Any from names above>

String - Name => Value pairs for each name listed in the names argument.

=back

=head3 RETURNS

Array Ref of Hash Refs where each Hash Ref has the following properties:

=over

=item set

String - name associated with the pair.

=item value

String - value of the item

=back

=cut

sub set {
    my ( $args, $result ) = @_;
    my @NAMES = split( /\|/, $args->get('names') );

    Cpanel::Logger::Soft::deprecated('The [asis,NVData::set] method is deprecated. Please use [asis,Personalization::set] instead.');

    my (@RSD);
    my $setmissing = $args->get('setmissing');
    my $nocache    = $args->get('__nvdata::nocache');
    foreach my $name (@NAMES) {
        my $conf = $args->get($name);
        $conf = defined $conf ? $conf : $Cpanel::FORM{$name};
        next if ( !$setmissing && !defined $conf );
        my $setname = $name;
        if ( $Cpanel::appname eq 'webmail' ) { $setname = $Cpanel::authuser . '_' . $name; }
        Cpanel::NVData::_set( $setname, ( defined $conf ? $conf : '' ), $nocache ? 1 : 0 );
        push( @RSD, { set => $name, value => $conf } );
    }

    $result->data( \@RSD );
    return 1;
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    get => $allow_demo,
    set => $allow_demo,
);

1;
