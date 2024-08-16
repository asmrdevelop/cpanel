package Cpanel::Market::SSL::Utils;

# cpanel - Cpanel/Market/SSL/Utils.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Market::SSL::Utils

=head1 DESCRIPTION

This module is here largely to host logic that L<Cpanel::Market::SSL>
primarily uses but that we want to test separately.

=cut

use Try::Tiny;

use Cpanel::ArrayFunc::Uniq      ();
use Cpanel::ASCII                ();
use Cpanel::Context              ();
use Cpanel::Exception            ();
use Cpanel::LoadModule           ();
use Cpanel::Regex                ();
use Cpanel::Sort::Multi          ();
use Cpanel::Validate::UTF8       ();
use Cpanel::WildcardDomain       ();
use Cpanel::WildcardDomain::Tiny ();

use constant _DCV_METHODS => qw( http dns );

=head1 FUNCTIONS

=head2 validate_subject_names_non_duplication( \@NAMES )

This throws a L<Cpanel::Exception::InvalidParameter> instance if there are
any duplicates or redundancies (e.g., a wildcard that secures a domain
that is also explicitly given).

Each NAME* is either a hash reference:

    {
        type => 'dNSName',
        name => $the_domain,
        ...,
    }

… or a two-member array reference:

    [ dNSName => $the_domain ]

The hash reference is the “preferred” format; the array reference is
supported for compatibility with any 3rd-party provider modules that might
have been created according to pre-v72 documentation.

=cut

sub validate_subject_names_non_duplication {
    my ( $subject_names_ar, $product_desc ) = @_;

    if ( !@$subject_names_ar ) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "Empty list of subject names!" );
    }

    #NB: Array is the old format
    my ( @names, @dcv_methods );
    for my $sn (@$subject_names_ar) {
        my ( $name, $dcv_method );

        if ( 'ARRAY' eq ref $sn ) {
            _verify_subject_name_type( $sn->[0] );
            ( $name, $dcv_method ) = ( $sn->[1], 'http' );
        }
        else {
            _verify_subject_name_type( $sn->{'type'} );

            $dcv_method = $sn->{'dcv_method'} or do {
                die Cpanel::Exception->create_raw("No “dcv_method” given for “$sn->{'name'}”");
            };

            if ( $dcv_method eq 'dns' ) {
                if ( !$product_desc->{'x_supports_dns_dcv'} ) {
                    die Cpanel::Exception::create_raw( 'InvalidParameter', "“$product_desc->{'display_name'}” does not support DNS-based DCV ($sn->{'name'})." );
                }
            }
            elsif ( $dcv_method ne 'http' ) {
                die Cpanel::Exception::create_raw( 'InvalidParameter', "“$sn->{'name'}” has an invalid “dcv_method” ($dcv_method)." );
            }

            $name = $sn->{'name'};
        }

        if ( $dcv_method ne 'dns' && Cpanel::WildcardDomain::Tiny::is_wildcard_domain($name) ) {
            die Cpanel::Exception::create_raw( 'InvalidParameter', "HTTP-based DCV cannot verify control of wildcard domains (e.g., $name)" );
        }

        push @names,       $name;
        push @dcv_methods, $dcv_method;
    }

    my @uniq_names = Cpanel::ArrayFunc::Uniq::uniq(@names);

    if ( @uniq_names != @names ) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "One or more duplicate subject names. (@names)" );
    }

    my ( @fqdns, @wildcards );
    for my $name (@names) {
        if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain($name) ) {
            push @wildcards, $name;
        }
        else {
            push @fqdns, $name;
        }
    }

    for my $fqdn (@fqdns) {
        for my $wildcard (@wildcards) {
            if ( Cpanel::WildcardDomain::wildcard_domains_match( $wildcard, $fqdn ) ) {
                die Cpanel::Exception::create_raw( 'InvalidParameter', "“$fqdn” is redundant with “$wildcard”." );
            }
        }
    }

    my %domain_dcv_method;
    @domain_dcv_method{@names} = @dcv_methods;

    return \%domain_dcv_method;
}

sub _verify_subject_name_type {
    my ($type) = @_;

    if ( $type ne 'dNSName' ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'This interface cannot fulfill certificate requests for subject names of type “[_1]”. [list_and_quoted,_2] [numerate,_3,is,are] the only allowed [numerate,_3,type,types].', [ $type, ['dNSName'], 1 ] );
    }

    return;
}

#----------------------------------------------------------------------

=head2 convert_subject_names_for_csr( SUBJECT_NAME1, SUBJECT_NAME2, .. )

This accepts SUBJECT_NAME* of either array reference (old) or hash reference
(new) form and returns a list of references suitable for insertion into
L<Cpanel::SSL::Create> as C<subject_names>.

=cut

sub convert_subject_names_for_csr {
    my (@snames) = @_;

    Cpanel::Context::must_be_list();

    my @new_list = map { ( 'ARRAY' eq ref ) ? $_ : [ @{$_}{ 'type', 'name' } ] } @snames;

    my @sorts = do {

        package Cpanel::Sort::Multi;
        (

            #Take dNSName entries first.
            sub { ( $b->[0] eq 'dNSName' ) cmp( $a->[0] eq 'dNSName' ) },

            #Take wildcards first.
            sub { index( $b->[1], '*' ) <=> index( $a->[1], '*' ) },

            #Take shorter first.
            sub { length( $a->[1] ) <=> length( $b->[1] ) },

            #Lexical sort, finally.
            sub { $a->[1] cmp $b->[1] },
        );
    };

    return Cpanel::Sort::Multi::apply( \@sorts, @new_list );
}

#----------------------------------------------------------------------

=head2 get_csr_domains_from_subject_names( \@SUBJECT_NAMES )

This returns an arrayref of domains (strings) for the CSR.
@SUBJECT_NAMES is as given to
C<Cpanel::Market::SSL::request_ssl_certificate()>.

=cut

sub get_csr_domains_from_subject_names {
    my ($subject_names_ar) = @_;

    my @csr_domains;

    for my $sn (@$subject_names_ar) {

        #The old way of notating “subject_names” was that
        #each item was a 2-member array.
        if ( 'ARRAY' eq ref $sn ) {
            push @csr_domains, $sn->[1];
        }

        #The new way is a hash reference; this is how clients
        #indicate DNS-based DCV (“dcv”) for a given domain.
        else {
            push @csr_domains, $sn->{'name'};
        }
    }

    return \@csr_domains;
}

=head2 normalize_subject_names( \@SUBJECT_NAMES )

This alters any arrays (i.e., the old format) in @SUBJECT_NAMES to be hashes
(i.e., the new format).

It will also populate C<dcv_method> on each hash, defaulting to C<http>
if no value is given.

=cut

sub normalize_subject_names {
    my ($subject_names_ar) = @_;

    for my $sn (@$subject_names_ar) {
        if ( 'ARRAY' eq ref $sn ) {
            my ( $type, $name ) = @$sn;

            $sn = {
                type       => $type,
                name       => $name,
                dcv_method => 'http',
            };
        }
        else {
            $sn->{'dcv_method'} ||= 'http';
        }
    }

    return;
}

#----------------------------------------------------------------------

=head2 validate_identity_verification( PRODUCT_IDEN_VERF, ORDER_IDEN_VERF )

This provides server-side validation of the special identity verification
data for OV and EV certificates.

=cut

sub validate_identity_verification {
    my ( $product_iden_ver, $order_iden_ver ) = @_;

    #Make sure $item_parts has all required parts.
    for my $ivpart (@$product_iden_ver) {
        my $name = $ivpart->{'name'};

        if ( !length $order_iden_ver->{$name} ) {
            if ( !$ivpart->{'is_optional'} ) {
                die Cpanel::Exception::create( 'MissingParameter', 'Provide the identity verification argument “[_1]”.', [$name] );
            }
        }

        next if !exists $order_iden_ver->{$name};

        my $val = $order_iden_ver->{$name};

        if ( defined $order_iden_ver->{$name} ) {
            try {
                _validate_identity_value($val);
            }
            catch {
                if ( try { $_->isa('Cpanel::Exception::Empty') } ) {
                    die Cpanel::Exception::create( 'Empty', [ name => $name ] );
                }

                local $@ = $_;
                die;
            };
        }

        local $ivpart->{'type'} = $ivpart->{'type'} || q<>;

        if ( $ivpart->{'type'} eq 'country_code' ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::CountryCodes');
            my $codes_ar = Cpanel::CountryCodes::COUNTRY_CODES();
            if ( !grep { $_ eq $val } @$codes_ar ) {
                die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” value ([_2]) is not a recognized [asis,ISO-3166-1] country code.', [ $name, $val ] );
            }
        }
        elsif ( $ivpart->{'type'} eq 'email' ) {
            Cpanel::LoadModule::load_perl_module('Email::Address::XS');
            if ( !Email::Address::XS->parse($val)->is_valid() ) {
                die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” value ([_2]) is not a valid email address.', [ $name, $val ] );
            }
        }
        elsif ( $ivpart->{'type'} eq 'date' ) {
            if ( $val !~ m<\A$Cpanel::Regex::regex{'YYYY_MM_DD'}\z> ) {
                die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” value ([_2]) is not a valid date in “[_3]” format.', [ $name, $val, 'YYYY-MM-DD' ] );
            }
        }
        elsif ( $ivpart->{'type'} eq 'duns_number' ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Validate::DUNS');
            Cpanel::Validate::DUNS::or_die($val);
        }
        elsif ( $ivpart->{'pattern'} && $val !~ m[$ivpart->{'pattern'}] ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” value ([_2]) is invalid.', [ $name, $val ] );
        }
    }

    #Make sure $item_parts has nothing unrecognized.
    for my $name ( keys %$order_iden_ver ) {
        if ( !grep { $_->{'name'} eq $name } @$product_iden_ver ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'This provider does not recognize the “[_1]” identity verification argument.', [$name] );
        }
    }

    return;
}

#----------------------------------------------------------------------

#This does a bit of basic validation:
#   - no control characters
#   - must be valid UTF-8
#   - no leading/trailing whitespace
#
sub _validate_identity_value {
    my ($value) = @_;

    if ( !length $value ) {
        die Cpanel::Exception::create('Empty');
    }

    my @ctrl_nums = Cpanel::ASCII::get_control_numbers();
    my $ctrl_str  = join q<>, map { chr } @ctrl_nums;

    if ( my @control = ( $value =~ m<([$ctrl_str])>g ) ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Encoder::ASCII');
        Cpanel::LoadModule::load_perl_module('Cpanel::ArrayFunc::Uniq');
        my @strs = Cpanel::ArrayFunc::Uniq::uniq( map { Cpanel::ASCII::get_symbol_for_control_number(ord) } @control );

        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” contains [numerate,_2,a control character,control characters] ([join,~, ,_3]). Such characters are prohibited.', [ Cpanel::Encoder::ASCII::to_hex($value), 0 + @control, \@strs ] );
    }

    if ( $value =~ m<\A\s|\s\z> ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Leading and trailing spaces are prohibited.' );
    }

    Cpanel::Validate::UTF8::or_die($value);

    return;
}

1;
