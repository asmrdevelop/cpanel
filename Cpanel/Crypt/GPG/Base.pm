package Cpanel::Crypt::GPG::Base;

# cpanel - Cpanel/Crypt/GPG/Base.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::Crypt::GPG::Base

=head1 SYNOPSIS

    use Cpanel::Crypt::GPG::Base ();
    my $gpg = Cpanel::Crypt::GPG::Base->new();

=head1 DESCRIPTION

Base class for several of the GPG modules.

=cut

use Cpanel::Binaries  ();
use Cpanel::Exception ();

=head1 PROPERTIES

=over

=item C<< bin >> [protected]

Path to the GPG binary.

=back

=head1 METHODS

=head2 new( \%opts_hr )

=head3 Purpose

Create a new instance of this class.

=head3 Arguments

=over 3

=item C<< \%opts_hr >> [in, optional]

A hashref with optional keys to use in the module.

=back

=head3 Returns

Returns a new instance of this class.

=head3 Throws

=over 3

=item When GPG cannot be found on the system

=back

=cut

sub new {
    my ( $class, $opts_hr ) = @_;

    $opts_hr = {} if !( $opts_hr && 'HASH' eq ref $opts_hr );

    my $bin = _find_gpg_or_die();

    my $obj = {
        'bin' => $bin,
        %{$opts_hr},
    };

    return bless $obj, $class;
}

=head2 get_gpg_bin()

=head3 Purpose

Getter for the bin setting.

=head3 Arguments

None

=head3 Returns

A string containing the path to the gpg binary for the object.

=cut

sub get_gpg_bin {
    my $self = shift;
    return $self->{bin};
}

=head1 PRIVATE METHODS

=head2 _find_gpg_or_die()

=head3 Purpose

Finds GPG on the system and dies if it cannnot.

=head3 Arguments

None

=head3 Returns

A string containing the path to the gpg binary.

=head3 Throws

=over 3

=item When GPG cannot be found on the system

=back

=cut

sub _find_gpg_or_die {
    my $bin = Cpanel::Binaries::path('gpg');
    -x $bin or die Cpanel::Exception::create( 'Unsupported', 'Only servers with [asis,GPG] support this module.' );
    return $bin;
}

1;
