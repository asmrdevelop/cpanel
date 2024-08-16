package Cpanel::Crypt::GPG::Import::Temp;

# cpanel - Cpanel/Crypt/GPG/Import/Temp.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Crypt::GPG::Import::Temp

=head1 SYNOPSIS

    use Cpanel::Crypt::GPG::Import::Temp ();

    my $gpg = Cpanel::Crypt::GPG::Import::Temp->new();
    $gpg->add_pub_key(key => $key);
    my ($valid, $sig) = $gpg->verify( sig => "test.file.asc", files => "test.file" );

    if ($valid) {
        print "Valid signature\nUID: $valid\nKey ID: $sig->{id}\n";
    }
    else {
        print "Invalid signature.\n";
    }

=head1 DESCRIPTION

Utilities to import and verify PGP/GPG keys and signatures all in a temporary directory.

See the L<Cpanel::Crypt::GPG::Import> documentation.

=cut

use strict;
use warnings;

use parent qw( Cpanel::Crypt::GPG::Import );

use Cpanel::TempFile ();

=head1 INSTANCE METHODS

=head2 new( \%opts_hr )

=head3 Purpose

Create a new instance of this class.
We extend the C<Cpanel::Crypt::GPG::Import> module here to allow
adding and verifying keys all in a temporary directory.

=head3 Arguments

=over 3

=item C<< \%opts_hr >> [in, optional]

A hashref with optional keys to use in the module.

=back

=head3 Returns

Returns a new instance of this class.

Returns undef on failure.

=cut

sub new {
    my ( $class, $opts_hr ) = @_;

    $opts_hr = {} if !( $opts_hr && 'HASH' eq ref $opts_hr );

    my $tmp  = Cpanel::TempFile->new;
    my $path = $tmp->dir();

    $opts_hr->{tmp}     = $tmp;
    $opts_hr->{homedir} = $path;

    my $self = $class->SUPER::new($opts_hr);

    return $self;
}

1;
