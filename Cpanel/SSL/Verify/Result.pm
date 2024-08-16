package Cpanel::SSL::Verify::Result;

# cpanel - Cpanel/SSL/Verify/Result.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::Verify::Result

=head1 SYNOPSIS

    use Cpanel::SSL::Verify;

    #In ordinary usage, this class is not instantiated directly but created
    #in response to a certificate chain verification.
    #
    my $result = Cpanel::SSL::Verify->new()->verify(...);

    $result->ok();  #0 or 1

    my $err = $result->get_error();         #e.g., CERT_HAS_EXPIRED
    my @errors = $result->get_errors_at_depth(0);

    my $depth = $result->get_max_depth();   #e.g, 3

    my $str = $result->get_error_string();  #human-readable, localized

    #----------------------------------------------------------------------
    # But if you must instantiate directly …

    my $result = Cpanel::SSL::Verify::Result->new(

        #The error state after X509_verify_cert():
        $err_name,              #e.g., CERT_HAS_EXPIRED

        #The certificate chain data, leaf-first:
        {
            errors => [ .. ],   #^^ ditto
            pem => '..',
            subject => '..',    #See below
        },
        #...,
    );

=head1 DISCUSSION

Note that C<get_error()> should usually, but not always, be redundant with the
C<get_errors_at_depth(0)>. We B<believe> that the only case where it is not
redundant is when there is no chain data; e.g., the verification doesn’t go
into the chain at all. See C<openssl/x509_vfy.c> for some cases where this can
happen.

The C<subject> in the chain data is redundant with C<pem>; however, since it’s
easily gotten from OpenSSL it doesn’t seem too bad. It’s purely for display,
so the specific format is irrelevant.

=cut

use cPstrict;

use Cpanel::Context    ();
use Cpanel::LoadModule ();

=head1 METHODS

=head2 $obj = I<CLASS>->new( ... )

Instantiates this class. See SYNOPSIS above.

=cut

sub new {
    my ( $class, $error, @chain_verify ) = @_;

    return bless [ $error, @chain_verify ], $class;
}

=head2 $yn = I<OBJ>->ok()

Returns a boolean that indicates whether verification succeeded.

=cut

sub ok {
    my ($self) = @_;

    return ( 'OK' eq $self->[0] ) ? 1 : 0;
}

=head2 $err = I<OBJ>->get_error()

Returns the “principal” error that this object represents.

=cut

sub get_error {
    my ($self) = @_;

    return $self->[0];
}

=head2 @errors = I<OBJ>->get_errors_at_depth( $DEPTH )

Returns the list of C<errors> that was given to C<new()> at
the specified $DEPTH. For example, depth 0 will give the errors
for the leaf certificate in the chain.

=cut

sub get_errors_at_depth {
    my ( $self, $depth ) = @_;

    die 'Need depth!' if !length $depth;

    Cpanel::Context::must_be_list();

    if ( !$self->[ 1 + $depth ] ) {
        die sprintf( 'Depth “%s” doesn’t exist! (max = %d)', $depth, $self->get_max_depth() );
    }

    return @{ $self->[ 1 + $depth ]{'errors'} };
}

=head2 $length = I<OBJ>->get_max_depth()

Returns a number that is one less than the number of certificates
in the chain.

=cut

sub get_max_depth {
    my ($self) = @_;

    return $#$self ? ( $#$self - 1 ) : undef;
}

=head2 $string = I<OBJ>->get_error_string()

Represents each certificate’s errors in this object via a single,
human-readable string.

=cut

sub get_error_string {
    my ($self) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Locale');

    if ( $#$self == 0 ) {
        my $locale = Cpanel::Locale->get_handle();

        return $locale->maketext( 'The certificate verification failed because of an error: [_1]', $self->[0] );
    }

    return $self->_chain_error_string();
}

#----------------------------------------------------------------------

sub _chain_error_string {
    my ($self) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Locale');

    my $locale;

    my @phrases;
    for my $n ( 1 .. $#$self ) {
        next if $self->[$n]{'ok'};

        $locale ||= Cpanel::Locale->get_handle();

        my $errs_ar = $self->[$n]{'errors'};

        push @phrases, $locale->maketext( 'Certificate #[numf,_1] ([_2]) has [quant,_3,validation error,validation errors]: [join,~, ,_4].', $n, $self->[$n]{'subject'}, 0 + @$errs_ar, $errs_ar );
    }

    return "@phrases";
}

1;
