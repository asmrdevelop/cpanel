package Cpanel::SSL::Objects::CABundle;

# cpanel - Cpanel/SSL/Objects/CABundle.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
no warnings;    ## no critic qw(ProhibitNoWarnings)

use Cpanel::LoadModule                ();
use Cpanel::SSL::Objects::Certificate ();
use Cpanel::LoadFile                  ();
my $locale;
my %trusted_certs_signatures;
my $_BASE64_CHAR = '[a-zA-Z0-9/+=]';
our $MAX_OBJECTS_IN_CACHE = 256;

our $_BASE64_CHAR_SPACES = $_BASE64_CHAR . '[a-zA-Z0-9/+=\s]+' . $_BASE64_CHAR;
our $CA_SIGNATURES_FILES = '/usr/local/cpanel/etc/cacert.signatures';

sub load_trusted_certificates_signatures {
    return \%trusted_certs_signatures if scalar keys %trusted_certs_signatures;

    %trusted_certs_signatures = map { $_ => 1 } split( m{\n}, Cpanel::LoadFile::load($CA_SIGNATURES_FILES) );

    return \%trusted_certs_signatures;
}

my %_cab_cache;

sub new {
    my ( $class, %OPTS ) = @_;

    my $cab = $OPTS{'cab'} or do {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'cab' ] );
    };

    return $_cab_cache{$cab} if $_cab_cache{$cab};

    my @issuers;
    my %subject;
    my %chain;
    while ( $cab =~ m{(-+BEGIN[^\n]+-+\s+$_BASE64_CHAR_SPACES\s*-+END[^\n]+-+)}gos ) {
        my $node = $1;
        my $cert_obj;
        eval { $cert_obj = Cpanel::SSL::Objects::Certificate->new( 'cert' => $node ) };
        if ($@) {
            my $err = $@;
            _get_locale();
            die $locale->maketext( 'CA Bundle #[numf,_1]: [_2]', 1 + scalar keys %subject, $err );
        }

        $subject{ $cert_obj->subject_text() } = $cert_obj;

        push @issuers, $cert_obj->issuer_text();

        if ( $cert_obj->subject_text() ne $cert_obj->issuer_text() ) {
            $chain{ $cert_obj->subject_text() } = $cert_obj;
        }
    }

    if ( !@issuers ) {
        die "Empty CAB! ($OPTS{'cab'})";
    }

    if ( scalar keys %_cab_cache > $MAX_OBJECTS_IN_CACHE ) {
        %_cab_cache = ();
    }

    return (
        $_cab_cache{ $OPTS{'cab'} } = bless {
            'issuers' => \@issuers,
            'chain'   => \%chain,
            'subject' => \%subject
        },
        $class
    );
}

#NOTE: The "not after" time is the last second in which a certificate is valid.
#This function compares all the certificates in the chain and returns the first
#"not after" time that it finds--i.e., the last second in which the CA bundle
#is valid.
sub get_earliest_not_after {
    my ($self) = @_;

    my @cert_objs  = values %{ $self->{'subject'} };
    my @not_afters = map { $_->parsed()->{'not_after'} } @cert_objs;

    return ( sort { $a <=> $b } @not_afters )[0];
}

#NOTE: The "not before" time is the first second in which a certificate is valid.
#This function returns the "not before" for the “leaf” certificate in the CA bundle.
sub get_not_before {
    my ($self) = @_;
    return $self->_get_leaf_node_property('not_before');
}

#This is for the “leaf” certificate.
sub get_modulus_length {
    my ($self) = @_;
    return $self->_get_leaf_node_property('modulus_length');
}

#For RSA, this is the same as get_modulus_length().
#For ECDSA, it’s a roughly-equivalent RSA modulus length.
sub get_encryption_strength {
    my ($self) = @_;

    my $key_alg = $self->_get_leaf_node_property('key_algorithm');

    local ( $@, $! );
    require Cpanel::Crypt::Algorithm;
    return Cpanel::Crypt::Algorithm::dispatch_from_object(
        $self->_get_leaf_node(),

        rsa => sub {
            return $self->get_modulus_length();
        },

        ecdsa => sub ($leaf) {
            require Cpanel::Crypt::ECDSA::Data;
            return Cpanel::Crypt::ECDSA::Data::get_equivalent_rsa_modulus_length( $leaf->ecdsa_curve_name() );
        },
    );
}

sub get_ecdsa_curve_name {
    my ($self) = @_;
    return $self->_get_leaf_node_property('ecdsa_curve_name');
}

sub _get_leaf_node ($self) {

    my ( $ok, $ordered_ar ) = $self->get_chain();
    die "Failed to get chain: $ordered_ar" if !$ok;

    return $ordered_ar->[0];
}

sub _get_leaf_node_property ( $self, $property ) {

    return $self->_get_leaf_node()->parsed()->{$property};
}

sub _subject_index {
    my ($self) = @_;
    return $self->{'subject'};
}

sub _subject_index_size {
    my ($self) = @_;
    return scalar keys %{ $self->_subject_index() };
}

sub _chain_index {
    my ($self) = @_;
    return $self->{'chain'};
}

sub _chain_index_size {
    my ($self) = @_;
    return scalar keys %{ $self->_chain_index() };
}

sub _issuers {
    my ($self) = @_;
    return $self->{'issuers'};
}

sub find_certificate_by_subject_text {
    my ( $self, $subject_text ) = @_;
    return $self->{'subject'}->{$subject_text};
}

sub find_leaf {
    my ($self) = @_;

    if ( !$self->_subject_index_size() ) {
        _get_locale();
        return ( 0, $locale->maketext('The CA bundle does not have any certificates.') );
    }

    my $leaf_subject;

    if ( $self->_chain_index_size() ) {

        # Here we make a copy of the chain index
        my %chain_copy = %{ $self->_chain_index() };

        # Then we remove all the certificates we have
        # matching the issuer line of the other certificates
        # in the bundle
        delete @chain_copy{ @{ $self->_issuers() } };

        # This should leave us with just the leaf
        if ( scalar keys %chain_copy != 1 ) {
            _get_locale();
            return ( 0, $locale->maketext('The CA bundle’s certificates do not form a chain.') );
        }

        $leaf_subject = ( keys %chain_copy )[0];
    }
    elsif ( $self->_subject_index_size() == 1 ) {
        $leaf_subject = ( keys %{ $self->{'subject'} } )[0];
    }

    return ( 1, $self->find_certificate_by_subject_text($leaf_subject) );

}

# This is how the TLS protocol wants these. Apache “error-corrects”
# incorrectly ordered CABs, but Lighttpd doesn’t. This is also optimized
# to omit trusted root certificates because the browser
# already has them, and it’s just a waste if we send them.
sub normalize_order_without_trusted_root_certs {
    my ($self) = @_;

    return ( 1, $self->{'_normalize_order_without_trusted_root_certs'} ) if $self->{'_normalize_order_without_trusted_root_certs'};

    my ( $ok, $ordered_ar ) = $self->get_chain_without_trusted_root_certs();
    return ( $ok, $ordered_ar ) if !$ok;

    return ( 1, $self->{'_normalize_order_without_trusted_root_certs'} = join( "\n", map { $_->text() } @$ordered_ar ) );
}

sub get_chain {
    my ($self) = @_;

    return $self->_get_chain( {} );
}

sub get_chain_without_trusted_root_certs {
    my ($self) = @_;

    return ( 1, $self->{'_get_chain_without_trusted_root_certs'} ) if $self->{'_get_chain_without_trusted_root_certs'};
    my ( $ok, $ordered_ar ) = $self->_get_chain( load_trusted_certificates_signatures() );
    return ( $ok, $ordered_ar ) if !$ok;
    $self->{'_get_chain_without_trusted_root_certs'} = $ordered_ar;
    return ( $ok, $ordered_ar );
}

# This function reorders the certificates in a cabundle
# so the lowest level (ones signed by the trusted root)
# come first. This matches the order of the TLS protocol itself.
sub _get_chain {
    my ( $self, $trusted_certs_signtures_ref ) = @_;

    my ( $status, $leaf ) = $self->find_leaf();

    return ( 0, $leaf ) if !$status;

    my @ordered_cab = ($leaf);

    #If there is more than one node, put the nodes in order.
    if ( $self->_chain_index_size() > 0 ) {
        my $current_node = $leaf;

        while ( $self->{'subject'}->{ $current_node->issuer_text() } ) {
            $current_node = $self->find_certificate_by_subject_text( $current_node->issuer_text() );
            push @ordered_cab, $current_node;
            last if ( $current_node->issuer_text() eq $current_node->subject_text() );
        }
    }

    if ( !$ordered_cab[0]->check_ca() ) {
        _get_locale();
        return ( 0, $locale->maketext('The [output,abbr,CA,Certificate Authority] bundle’s root node must identify itself as a CA certificate.') );
    }

    my @cleaned_up_ordered_cab;
    foreach my $cert_obj (@ordered_cab) {
        my $signature = $cert_obj->signature();
        my $text      = $cert_obj->text();

        # Do not include trusted certificates
        # in the ordered bundle as it just increases
        # the size of the cab
        next if $trusted_certs_signtures_ref->{$signature};

        push @cleaned_up_ordered_cab, $cert_obj;
    }

    return ( 1, \@cleaned_up_ordered_cab );
}

sub _get_locale {
    Cpanel::LoadModule::load_perl_module('Cpanel::Locale') if !$INC{'Cpanel/Locale.pm'};
    return $locale ||= Cpanel::Locale->get_handle();
}

1;
