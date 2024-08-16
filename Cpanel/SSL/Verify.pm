package Cpanel::SSL::Verify;

# cpanel - Cpanel/SSL/Verify.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::Verify - Certificate chain verification

=head1 SYNOPSIS

    my $verify = Cpanel::SSL::Verify->new();

    #Each argument gets split apart, so concatenated PEM works.
    #(This includes $leaf_pem; i.e., that argument can be a
    #newline-concatenated string of certificate PEMs.)
    #
    #The first cert must be the leaf node; others can be in any order.
    #
    #The return is an instance of Cpanel::SSL::Verify::Result.
    #
    my $v = $verify->verify( $leaf_pem, @cab_pem );

    die $v->error_string() if !$v->ok();

=head1 MEMORY PROBLEMS

OpenSSL and/or Perl appear to have some pretty bad memory leakage issues
around here. B<DO NOT> use this code in any daemons, please!

=cut

use cPstrict;

use Cpanel::SSL::Verify::Result ();

#like the environment variable; used for testing
our $_SSL_CERT_FILE;

sub new {
    my ($class) = @_;

    require Net::SSLeay;
    require Cpanel::NetSSLeay::BIO;
    require Cpanel::NetSSLeay::X509;
    require Cpanel::NetSSLeay::X509_STORE;
    require Cpanel::NetSSLeay::X509_STORE_CTX;
    require Cpanel::NetSSLeay::X509_VERIFY_PARAM;
    require Cpanel::OpenSSL::Verify;

    require Cpanel::ArrayFunc::Uniq;

    Net::SSLeay::initialize();

    my $self = bless {
        '_bio_obj'        => Cpanel::NetSSLeay::BIO->new_s_mem(),
        '_root_cert_file' => $_SSL_CERT_FILE || $class->_get_root_cert_file(),
    }, $class;

    return $self;
}

sub verify {
    my ( $self, @chain ) = @_;

    my ( $leaf_pem, @untrusted ) = map { split m[(?<=-)\n+(?=-)] } @chain;

    $self->_setup_store_if_needed();

    my $cert_to_check = Cpanel::NetSSLeay::X509->new( $self->{'_bio_obj'}, $leaf_pem );

    my $store_ctx = $self->{'x509_store_ctx'};

    $store_ctx->init(
        $self->{'x509_store'},
        $cert_to_check,
        @untrusted,
    );

    @{ $self->{'_chain_verify'} } = ();

    $store_ctx->verify_cert();

    #For some reason we get duplicate errors with a self-signed certificate,
    #so do a uniq() here. The duplicates MAY be because of setting the verify
    #callback on the X509_STORE object rather than X509_STORE_CTX; i.e., the
    #callback propagates to the X509_STORE_CTX during the verify, then it runs
    #for the X509_STORE at the end … maybe?? Unsure. Anyway, setting the
    #callback on the X509_STORE is what OpenSSL’s apps/verify.c does, so we
    #might as well follow that example.
    for ( @{ $self->{'_chain_verify'} } ) {
        $_->{'errors'} = [ Cpanel::ArrayFunc::Uniq::uniq( @{ $_->{'errors'} } ) ];
    }

    #We have to indicate a separate “error” because the callback may never
    #have been called. See X509_verify_cert() in openssl/x509_vfy.c.
    return Cpanel::SSL::Verify::Result->new(
        _err_str( $store_ctx->get_error() ),
        @{ $self->{'_chain_verify'} },
    );
}

#----------------------------------------------------------------------

sub _get_root_cert_file {
    require Mozilla::CA;
    return Mozilla::CA::SSL_ca_file();
}

sub _err_str {
    return Cpanel::OpenSSL::Verify::error_code_to_name( $_[0] ) || $_[0];
}

sub _setup_store_if_needed {
    my ($self) = @_;

    if ( $self->{'x509_store_ctx'} ) {

        # If the x509_store_ctx already exists we need to call
        # X509_STORE_CTX_cleanup before we can do X509_STORE_CTX_init
        # for another verify run.
        #
        # see https://www.openssl.org/docs/manmaster/crypto/X509_STORE_CTX_new.html
        $self->{'x509_store_ctx'}->cleanup();

        return 1;
    }

    $self->{'x509_store'} = Cpanel::NetSSLeay::X509_STORE->new();
    $self->{'x509_store'}->load_locations( $self->{'_root_cert_file'} );

    $self->{'x509_store_ctx'} = Cpanel::NetSSLeay::X509_STORE_CTX->new();
    $self->{'x509_store_ctx'}->set_bio( $self->{'_bio_obj'} );

    _enable_trusted_first_config( $self->{'x509_store'} );

    my $store_ctx = $self->{'x509_store_ctx'};

    $self->{'_chain_verify'} = [];

    #XXX: This part is leaky.
    $self->{'x509_store'}->set_verify_callback(
        \&_verify_callback,
        [ $store_ctx, $self->{'_chain_verify'} ],
    );

    return 1;
}

sub _enable_trusted_first_config ($x509_store) {

    # Tell OpenSSL to “go out of its way” to verify a given cert chain,
    # even if that means ignoring some of the certs given to the verify
    # function. This is important because it allows us to use the cert
    # chain that Let’s Encrypt, by default, sends via its API as of
    # 1 Oct 2021, which includes an intermediate that points to an expired
    # trust anchor. We need to *ignore* that intermediate and instead let
    # OpenSSL notice it doesn’t *need* that intermediate; it can validate
    # the certificate chain via a self-signed root in its own trusted
    # root store.
    #
    # (Let’s Encrypt sends this chain because it retains compatibility
    # with old Android clients that--by design--ignore trust anchor
    # expiration.)
    #
    # OpenSSL 1.1.1 always enables this option, so once we drop 1.0.2
    # (CentOS 7 et al.) and 1.0.1 (CloudLinux 6) we can remove this:

    my $verify_params = Cpanel::NetSSLeay::X509_VERIFY_PARAM->new();
    $verify_params->set_flags( Net::SSLeay::X509_V_FLAG_TRUSTED_FIRST() );

    $x509_store->set1_param($verify_params);

    return;
}

sub _verify_callback {
    my ( $ok, $store_ctx_ptr, $other_args ) = @_;

    my ( $sctx, $chain_verify_ar ) = @$other_args;

    my $depth = $sctx->get_error_depth();
    $chain_verify_ar->[$depth]{'ok'} //= $ok;

    my $node = $chain_verify_ar->[$depth];
    $node->{'ok'} &&= $ok;

    #Include the subject string as a courtesy; it’s not strictly
    #necessary when we also include the certificate PEM.
    if ( !$node->{'subject'} ) {
        if ( my $x509 = $sctx->get_current_cert() ) {
            @{$node}{ 'subject', 'pem' } = ( $x509->get_subject_string(), $x509->get_pem() );
        }
    }

    my $err_str = _err_str( $sctx->get_error() );
    if ( $err_str ne 'OK' ) {
        push @{ $chain_verify_ar->[$depth]{'errors'} }, $err_str;
    }
    else {
        $chain_verify_ar->[$depth]{'errors'} ||= [];
    }

    return;
}

sub DESTROY {
    my ($self) = @_;

    # order matters to prevent SEGV
    undef $self->{'x509_store_ctx'};
    undef $self->{'x509_store'};
    return 1;
}

1;
