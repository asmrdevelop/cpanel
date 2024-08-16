package Cpanel::Server::TLSCache;

# cpanel - Cpanel/Server/TLSCache.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::TLSCache - round-robin SNI caching

=head1 SYNOPSIS

    #Args are those to pass to IO::Socket::SSL::SSL_Context
    my $tlscache = Cpanel::Server::TLSCache->new(

        # See below for discussion of input options.
        ctx_key1 => ctx_value1,
        ctx_key2 => ctx_value2,
    );

    while ( my $to_client = $server->accept() ) {
        $tlscache->check();

        my $pid = fork or do {
            if ( my $ctx = $tlscache->get_ctx_for_domain($servername) ) {
                #activate the $ctx
            }
        };
    }

=head1 DESCRIPTION

This allows cpsrvd to cache OpenSSL CTX objects. It works thus, from an initial
state with nothing cached:

=over 4

=item 1. The parent process instantiates this class.

=item 2. The child receives a request for the TLS C<servername> and passes
that into this class’s C<get_ctx_for_domain()> method. That method looks
for a cert for the given FQDN or its corresponding wildcard (e.g.,
C<foo.bar.com> => C<*.bar.com>); either one will satisfy the client’s
request. We first check this object’s memory cache to see if we already
have an OpenSSL CTX for either name. If that fails, then check the
L<Cpanel::Domain::TLS> datastore.

If there nothing there for either name,
there’s nothing else for this class to do. (The calling logic must then
handle fallback to some generic SSL certificate.)

=item 3. OK, so we found a cert in L<Cpanel::Domain::TLS>’s datastore
that matches the domain passed into C<get_ctx_for_domain()>? Cool. We
first create a new CTX object for the newly-loaded resources. This is what
the current child process will (eventually) send back to the client.

=item 4. The child sends the loaded name (either C<servername> or the
wildcard … whichever matches the cert for the brand-new CTX object) back
to the parent. The child is now done. It sends the certificate back to the
client and continues on its merry way.

=item 5. The parent then calls C<check()>--presumably after its next socket
C<accept()>. C<check()> will, if it finds anything, add to the memory cache
as appropriate; the next child process will then have a CTX object for that
name loaded in memory. (The parent should probably call C<check()> in a loop
until there is nothing to report back.)

=back

This is kept from “blowing up” in terms of memory usage by treating the
CTX cache as a queue of finite size; once we have too many CTX objects,
we remove the oldest to make room for the new.

=head1 “FALLBACK” MODE

In some contexts (e.g., when cpsrvd handles service subdomains) it is useful
to implement the following behavior:

If there is no Domain TLS certificate for the given C<servername>, but that
C<servername> matches one of a defined set of DNS prefixes, then strip that
prefix from the C<servername> then do a fallback lookup against that shorter
name.

If that fallback lookup fails, then determine which cPanel user owns the short
name, and determine which web vhost corresponds to it. Serve up the SSL
certificate, if any, from Apache TLS for that web vhost.

For example: if C<cpanel> is one of the designated prefixes that triggers the
fallback behavior, and an SNI request comes in for C<cpanel.example.com>, then
if Domain TLS has no certificate for C<cpanel.example.com>, then we’ll serve
up Domain TLS’s certificate for C<example.com> if one exists.
If one doesn’t exist, then we look up who owns C<example.com>, look up which
web virtual host pertains to that domain, then serve up that web virtual
host’s SSL certificate.

=head2 Rationale

httpd is what normally handles TLS for service subdomains over port 443;
however, when httpd is disabled, cpsrvd handles that duty. cpsrvd doesn’t
have easy access to Apache’s domain-to-vhost resolution logic, and
implementing it is expensive.

Almost all of the time, though, the service subdomain’s immediate ancestor
(C<example.com> in the example above) will be in Domain TLS; the only cases
where that doesn’t happen would be when a certificate secures the service
subdomain but not the parent domain.

An alternative to this approach would be to create and to maintain Domain TLS
entries for service subdomains; however, that has a lot of overhead because
service subdomains can be overridden, and they can be enabled and disabled.

Given the rarity of needing to do a full vhost lookup and the maintenance
advantage of forgoing the overhead of separate Domain TLS entries for service
subdomains, the approach just described is judged reasonable.

=head1 METHODS

=cut

use strict;
use warnings;

use constant {
    DEBUG     => 0,
    CACHE_TTL => 600,    #10 minutes

    _EAGAIN => 11,
};

use Net::SSLeay ();

use Cpanel::Domain::TLS       ();    # PPI NO PARSE - used below
use Cpanel::FHUtils::Blocking ();
use Cpanel::NetSSLeay         ();
use Cpanel::NetSSLeay::CTX    ();
use Cpanel::NetSSLeay::EC_KEY ();
use Cpanel::Server::TLSLookup ();

*_ssleay = \&Cpanel::NetSSLeay::do;
*_time   = *CORE::time;

our $MAX_CTX_COUNT_TO_CACHE = 100;

my $can_ecdh;                        # Is ECDH Key Exchange available with Net::SSLeay
my @DEFAULT_SSL_OP;

BEGIN {

    # 1.0.1d has broken ECDH on 64bit
    #NB: Copied from IO/Socket/SSL.pm
    $can_ecdh = Net::SSLeay->can('CTX_set_tmp_ecdh') && ( Net::SSLeay::OPENSSL_VERSION_NUMBER() != 0x1000104f );

    @DEFAULT_SSL_OP = qw(ALL SINGLE_DH_USE);

    if ($can_ecdh) {
        push @DEFAULT_SSL_OP, 'SINGLE_ECDH_USE';
    }
}

#cf. RFC 1035, section 2.3.4
my $MAX_DNS_LENGTH = 256;
my $MSG_LENGTH     = $MAX_DNS_LENGTH;

my $PACKAGE = __PACKAGE__;

=head2 I<CLASS>->new( key1 => value1, key2 => value2, … )

Instantiates this class.

The following arguments are recognized;
these mimic the behavior of corresponding arguments to
L<IO::Socket::SSL::SSL_Context>.

=over

=item * C<SSL_cipher_list>

=item * C<SSL_honor_cipher_order>

=item * C<SSL_dh>

=item * C<SSL_ecdh_curve>

=back

=cut

sub new {
    my ( $class, @args ) = @_;

    my %args_hash = (
        SSL_honor_cipher_order => 1,
        SSL_ecdh_curve         => 'prime256v1',
        @args,
    );

    local ( $!, $^E );

    #There are multiple ways of accomplishing child-to-parent IPC.
    #Currently this uses a pipe; a message queue would be another option.
    #The kernel in C6 appears to store 65 KiB in either, whereas C7
    #seems to store only 16 KiB in a message queue.
    pipe( my $rdr, my $wtr ) or die "pipe() failed: $!";

    Cpanel::FHUtils::Blocking::set_non_blocking($rdr);
    Cpanel::FHUtils::Blocking::set_non_blocking($wtr);

    my $self = {
        _pid => $$,

        _rdr => $rdr,
        _wtr => $wtr,

        _ctx_args => \%args_hash,

        # XXX TODO: These two need to be kept in sync explicitly.
        # Create an IndexedArray object.
        # NOTE: _domain_ctx is accessed from tests.
        _domain_ctx     => {},
        _cached_domains => [],
    };

    return bless $self, $class;
}

=head2 I<OBJ>->check()

Returns the domain that has been cached,
or undef if no domain was requested. Call this from the parent process.

=cut

sub check {
    my ($self) = @_;

    warn "PID $$: Checking SSL CTX cache …\n" if DEBUG;

    local ( $!, $^E );

    #For now, each domain message uses 256 bytes. Realistically,
    #that should be fine, as Linux’s pipe buffer max is 64 KiB,
    #and if we get 256 child processes that each enqueue a domain
    #without having the parent collect those, that’s a problem
    #with what’s calling into this module.
    my $ok = sysread(
        $self->{'_rdr'},
        my $read_buffer,
        $MSG_LENGTH,
    );

    if ($ok) {
        $read_buffer =~ s<\0+\z><>;
        warn "$$: Received domain cache request: “$read_buffer”\n" if DEBUG;

        $self->_add_domain($read_buffer);
        return $read_buffer;
    }

    #EAGAIN just means there was nothing to read.
    elsif ( $! != _EAGAIN() ) {
        die "$PACKAGE - read() failed: $!";
    }

    return undef;
}

sub _add_domain {
    my ( $self, $domain ) = @_;

    warn "PID $$: Caching CTX for “$domain” …\n" if DEBUG;

    my $ctx = $self->_create_ctx_for_domain($domain);

    $self->_expire_one_ctx() while @{ $self->{'_cached_domains'} } >= $MAX_CTX_COUNT_TO_CACHE;

    #This is why these two data structures should be one object.
    push @{ $self->{'_cached_domains'} }, $domain;
    $self->{'_domain_ctx'}{$domain}          = $ctx;
    $self->{'_domain_cache_expiry'}{$domain} = _time() + CACHE_TTL();

    return;
}

sub _expire_one_ctx {
    my ($self) = @_;

    my $exp_domain = shift @{ $self->{'_cached_domains'} };

    #This should fire the DESTROY handler on Cpanel::NetSSLeay::CTX.
    my $exp_ctx = delete $self->{'_domain_ctx'}{$exp_domain};

    return;
}

#----------------------------------------------------------------------

#common to both parent and child
sub _create_ctx_for_domain {
    my ( $self, $domain ) = @_;

    warn "PID $$: Creating TLS ctx for domain “$domain”.\n" if DEBUG;

    my $path;

    #This is, somewhat surprisingly, faster than loading the file
    #once and creating OpenSSL objects from memory. (And *much* faster
    #than loading an equivalent PKCS12 file!)
    #
    #It’s also as fast as loading dedicated key and cert chain files.

    my ( $tls_entry, $is_domain_tls ) = Cpanel::Server::TLSLookup::get_domain_and_info($domain);

    if ($tls_entry) {
        my $rdr = $is_domain_tls && 'Cpanel::Domain::TLS';

        $rdr ||= do {
            local ( $!, $@ );
            require Cpanel::Apache::TLS;    # PPI NO PARSE - it’s used
            'Cpanel::Apache::TLS';
        };

        $path = $rdr->get_tls_path($tls_entry);
    }

    return $path && $self->_load_pem_to_ctx($path);
}

sub _load_pem_to_ctx {
    my ( $self, $pem_path ) = @_;

    my $ctx_obj = Cpanel::NetSSLeay::CTX->new();

    $ctx_obj->set_options( @DEFAULT_SSL_OP, $self->{'_ctx_args'}{'SSL_honor_cipher_order'} ? 'CIPHER_SERVER_PREFERENCE' : () );

    if ( $self->{'_ctx_args'}{'SSL_dh'} ) {
        $ctx_obj->set_tmp_dh( $self->{'_ctx_args'}{'SSL_dh'} );
    }

    if ( $can_ecdh && $self->{'_ctx_args'}{'SSL_ecdh_curve'} ) {
        $ctx_obj->set_tmp_ecdh( Cpanel::NetSSLeay::EC_KEY->new( $self->{'_ctx_args'}{'SSL_ecdh_curve'} ) );
    }

    if ( $self->{'_ctx_args'}{'SSL_cipher_list'} ) {
        $ctx_obj->set_cipher_list( $self->{'_ctx_args'}{'SSL_cipher_list'} );
    }

    $ctx_obj->use_certificate_chain_file($pem_path);
    $ctx_obj->use_PrivateKey_file( $pem_path, 'PEM' );

    return $ctx_obj;
}

#----------------------------------------------------------------------
# TODO: Separate the “child” behavior from the “parent”

=head2 I<OBJ>->get_ctx_for_domain( 'thedomain.tld' )

This will look for a certificate for the given domain in Domain TLS’s
datastore. If it finds one, it will return a L<Cpanel::NetSSLeay::CTX>
instance for the given domain. Otherwise, it returns undef.

Call this from the B<child> process; the parent’s subsequent call to
C<check()> will then cache a CTX object for subsequent SNI requests for
the given domain.

=cut

sub get_ctx_for_domain {
    my ( $self, $domain ) = @_;

    if ( length $domain > $MAX_DNS_LENGTH ) {
        die "“$domain” is longer than $MAX_DNS_LENGTH characters, the length limit on DNS names!";
    }

    my $ctx = $self->_get_ctx_from_cache($domain);
    $ctx ||= $self->_create_and_enqueue_ctx_for_domain($domain);

    return $ctx;
}

sub _get_ctx_from_cache {
    my ( $self, $domain ) = @_;

    my $ctx = $self->{'_domain_ctx'}{$domain};
    if ( $ctx && ( $self->{'_domain_cache_expiry'}{$domain} > _time() ) ) {
        return $ctx;
    }

    return undef;
}

sub _create_and_enqueue_ctx_for_domain {
    my ( $self, $domain ) = @_;

    my $ctx;

    local $@;

    # Try is too slow here
    eval {
        $ctx = $self->_create_ctx_for_domain($domain);

        #Closing this handle doesn’t seem to be necessary, and omitting it
        #simplifies SSL_Context.pm’s test. I’m leaving it in, though,
        #for reference in case there’s ever a blocking problem.
        #undef $self->{'_rdr'};

        my $ok = syswrite(
            $self->{'_wtr'},
            $domain . ( "\0" x ( $MSG_LENGTH - length $domain ) ),
        );
        warn "$PACKAGE write() failed: $!" if !$ok;
    };
    warn if $@;

    return $ctx;
}

#----------------------------------------------------------------------

1;
