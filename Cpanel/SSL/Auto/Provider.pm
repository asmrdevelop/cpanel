package Cpanel::SSL::Auto::Provider;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Provider - base class for AutoSSL provider modules

=head1 SYNOPSIS

    package Cpanel::SSL::Auto::Provider::MySSLProvider;

    use parent qw( Cpanel::SSL::Auto::Provider );

    sub renew_ssl_for_vhosts { ... }

    #See below for other useful methods to define.

    #-----------------------------------------------------------------
    package main;

    my $obj = Cpanel::SSL::Auto::Provider::MySSLProvider->new();

    $obj->start_logging($username_or_undef);        #start a new log
    $obj->resume_logging('2016-05-09T05:34:12Z');   #append to an existing one

    $obj->log('success', 'It worked!');
    $obj->log('info', 'Just FYI, …');
    $obj->log('warn', 'Hm, this may not be right …');
    $obj->log('info', 'Uh-oh …');

    $obj->get_log_start_time();

    $obj->keep_log_in_progress();

    #-----------------------------------------------------------------

    $obj->renew_ssl_for_vhosts( $username, vhname1 => \@domains1, ... );

    my $pretty = $obj->DISPLAY_NAME();
    my $days = $obj->DAYS_TO_REPLACE();
    my $max_domains = $obj->MAX_DOMAINS_PER_CERTIFICATE();

    if ( $obj->CERTIFICATE_IS_FROM_HERE($pem) ) { ... }

    my @props = $obj->PROPERTIES();
    $obj->EXPORT_PROPERTIES( key1 => value1, ... );

    $obj->RESET();

=head1 DESCRIPTION

This class defines baseline functionality for AutoSSL provider modules.
You should never instantiate this class directly; instead, you should
create subclasses to define AutoSSL provider behavior, and instantiate
those modules

=head1 HOW TO MAKE A PROVIDER MODULE

The first requirement for provider modules is that they subclass this
module.

Additionally provider modules must be namespaced under
C<Cpanel::SSL::Auto::Provider> and reside under one of these two
directories:

=over 4

=item C</usr/local/cpanel>: cPanel-provided modules

=item C</var/cpanel/perl>: Third-party modules

=back

For example, a third-party module “MikesSSL” would be named
C</var/cpanel/perl/Cpanel/SSL/Auto/Provider/MikesSSL.pm>.

=cut

#----------------------------------------------------------------------

use cPstrict;

use parent qw( Cpanel::Output::Container );

use Try::Tiny;

use Cpanel::Imports;

use Cpanel::Apache::TLS       ();
use Cpanel::Debug             ();
use Cpanel::Context           ();
use Cpanel::Exception         ();
use Cpanel::Hooks             ();
use Cpanel::Domain::Owner     ();
use Cpanel::LoadModule        ();
use Cpanel::LoadModule::Utils ();
use Cpanel::Sort::Multi       ();
use Cpanel::Set               ();

#overridden in tests
our $LOGGER_CLASS = 'Cpanel::SSL::Auto::Log';

#----------------------------------------------------------------------

=head1 REQUIRED SUBCLASS METHODS

=head2 renew_ssl( %OPTS )

This method will take precedence over C<renew_ssl_for_vhosts()>.
All new AutoSSL provider modules should implement C<renew_ssl()>
rather than C<renew_ssl_for_vhosts()>.

C<renew_ssl()> creates new SSL certificates for the given domains and
installs them on the associated vhosts. This may be done synchronously
or asynchronously, as a result of which there is no return value.

It is suggested that a notification be sent to inform the user of the status
of the SSL issuances and installations once they’re complete.

(NB: As of 11.74, C<vhost name> is just the Apache ServerName. It is
possible that this may change in the future, however!)

The %OPTS passed in are:

=over

=item * C<username> - a string

=item * C<vhost_domains> - a hash reference; keys are the vhost names, and
the values are the full list of domains to be included in the vhost’s
certificate.

=item * C<dcv_method> - (hash - only given when C<get_vhost_dcv_errors()>
is not present) The local DCV method (either C<http> or C<dns>)
that succeeded for each domain.

=item * C<single_domains> - An array of domain names that need SSL and
that B<must> be on their own certificate, I<explicitly>. (i.e., wildcard
substitution B<MUST> B<NOT> happen!)

=back

#----------------------------------------------------------------------

=head2 renew_ssl_for_vhosts( USERNAME, VHOST1 => \@DOMAINS1, VHOST2 => … )

This is the historical forerunner of C<renew_ssl()>. That function’s
C<vhost_domains> is expressed as a flat list of key/value pairs, as a
result of which it is not feasible to express C<dcv_method> to this
function.

All provider modules should favor C<renew_ssl()> rather than this method.

=cut

sub renew_ssl_for_vhosts { die 'Unimplemented' }

=head2 CAA_STRING()

A string to be used in created CAA records in the zone's DNS. As of
September 2017 all CAs must validate CAA records; thus, all AutoSSL
providers must implement this method.

=cut

sub CAA_STRING { die 'Unimplemented' }

#----------------------------------------------------------------------

=head1 OPTIONAL SUBCLASS METHODS

=head2 EXTRA_CAA_STRINGS()

Returns a list of CAA strings that AutoSSL’s pre-DCV CAA verification
will recognize, in addition to the CAA_STRING() value, as permitting issuance.
For example, Sectigo, as of this writing, recognizes C<comodoca.com>
in addition to C<sectigo.com>.

=cut

use constant EXTRA_CAA_STRINGS => ();

#----------------------------------------------------------------------

=head2 CHECK_FREQUENCY()

A string that indicates the frequency with which AutoSSL should invoke
the check logic via cron. The default value is C<daily>; C<3hours> is
also recognized (i.e., to check every 3 hours).

=cut

use constant CHECK_FREQUENCY => 'daily';

#----------------------------------------------------------------------

=head2 SUPPORTS_WILDCARD()

Returns a boolean that indicates whether the provider can issue
certificates that include wildcard domains.

=cut

use constant SUPPORTS_WILDCARD => 0;

#----------------------------------------------------------------------

=head2 DAYS_TO_REPLACE()

An integer number of days that indicates how long of a period prior
to certificate expiration is acceptable before we try to replace the
certificate. For example, if you set 15 as the return here, then once
the certificate is less than 15 days away from expiration, AutoSSL
will begin trying to replace it.

If a provider does not set this value, then the certificate may not
be replaced until it is already expired.

=cut

sub DAYS_TO_REPLACE { return undef }

#----------------------------------------------------------------------

=head2 SUPPORTS_ANCESTOR_DCV()

Indicates whether the provider module supports ancestor domain substitution
in DCV; e.g., if the remote Certificate Authority will attempt and accept
DCV against, e.g., C<example.com> as a substitute for DCV against, e.g.,
C<foo.example.com>. (Sectigo does this; Let’s Encrypt does not.)

As of late 2021, CAs will no longer honor this with HTTP DCV;
hence, this B<ONLY> now applies to DNS DCV. (Previously it encompassed
either DCV type.)

=cut

use constant SUPPORTS_ANCESTOR_DCV => 0;

=head2 SSL_VERIFY_USES_TRUSTED_FIRST

Assume the following certificate chain: A (leaf) - B - C - D (trusted).
Assume that D is expired. Now assume that trusted node E also exists, is
B<NOT> expired, and can validate node B; i.e., A-B-E is valid. Assume that
all clients know about node D, but fewer are node-E aware.

What will a TLS client do when a server sends it the A-B-C chain? You
might think, since this chain depends on an expired trusted root (D), that
the client would fail the verification. In fact, though, if that client
has the E trusted node, then our TLS client will probably B<ACCEPT> this
trust chain: it’ll just ignore the C node and verify A-B-E.

Other clients accept that chain via different logic: they just B<disregard>
entirely the concept of trusted-root expiry. For such a client, A-B-C-D
is a perfectly valid chain, even if there’s no node E around.

Servers could thus, when a client connects, validly send either the A-B-C
or A-B certificate chain. A-B, though, would break client that lack node E;
thus, sending A-B-C is the most sensible path.

OpenSSL, though, presents a special problem: in pre-1.1.0 versions of the
library, I<standalone> certificate chain verification B<FAIL>s the
A-B-C chain by default because, unlike the connection verification logic,
standalone verification does B<NOT> ignore node C.

AutoSSL uses standalone verification as part of determination of whether
to request a new certificate for a given domain set; thus, if standalone
verification behaves differently from connection verification, that’s a
problem.

Modern cPanel & WHM versions rectify this by configuring OpenSSL’s
standalone verification in “trusted-first” mode. This is how version 1.1.0
and later of that library I<always> works, but in 1.0.2 (CentOS 7) and
earlier we have to configure it manually.

Some AutoSSL plugins, though—e.g., the Let’s Encrypt plugin—run in
outdated cPanel & WHM versions. Such plugins thus need an indicator of
whether it’s “safe” to use the A-B-C chain.

This flag is that indicator; plugins can query for its existence and,
if it’s there, know that the A-B-C chain is safe to use; otherwise, A-B
is the only option.

=cut

use constant SSL_VERIFY_USES_TRUSTED_FIRST => 1;

=head2 REQUEST_URI_DCV_PATH()

An Apache regular expression that describes the path for DCV files.
cPanel will exclude these from its domain redirections. (See the
documentation for Apache’s “RewriteCond” directive.) This is useful,
e.g., if you’ve redirected an entire domain but still want SSL on the
original domain.

=cut

sub REQUEST_URI_DCV_PATH { return undef }

=head2 URI_DCV_RELATIVE_PATH()

A directory path relative to the document root of the domain the DCV
will check. This path appended onto the document root to check
DCV files in subdirectories of the document root for the domain.
If this isn't specified the DCV file will be checked in the document root for
the domain.

=cut

sub URI_DCV_RELATIVE_PATH { return undef }

=head2 URI_DCV_ALLOWED_CHARACTERS()

An array reference of characters that are allowed in the random portion of
a DCV filename. The characters specified here will be the ones used to randomly
generate a DCV filename for running local DCV checks. DCV filenames are composed of
two parts with a '.' joining them: random characters + . + extension
If this is not specified, the DCV check will be performed with default values for the
randomized DCV filename.

=cut

sub URI_DCV_ALLOWED_CHARACTERS { return undef }

=head2 URI_DCV_RANDOM_CHARACTER_COUNT()

An integer that specifies the number of characters that are allowed in the
random portion of a DCV filename. DCV filenames are composed of two parts
with a '.' joining them: random characters + . + extension
If this is not specified a default character count will be used.

=cut

sub URI_DCV_RANDOM_CHARACTER_COUNT { return undef }

=head2 DCV_USER_AGENT()

A scalar string that specifies the HTTP user agent string to use when
imitating the DCV check of the provider. If not defined a default string
will be used.

=cut

sub DCV_USER_AGENT { return undef }

=head2 EXTENSION()

A scalar string that specifies the DCV filename extension, if any.
This may be undef or empty string to indicate that no extension is used.
DCV filenames are composed of two parts with a '.' joining them:
random characters + . + extension

=cut

sub EXTENSION { return undef }

=head2 USE_LOCAL_DNS_DCV()

Indicates whether to use cPanel & WHM’s logic for DNS-based DCV as
part of local DCV. For historical reasons this defaults to 0 (off),
but it is recommended that any providers that can support DNS-based DCV
enable this flag. This will mean that C<get_vhost_dcv_errors()> and
C<renew_ssl()> can receive C<dcv_method> values of C<dns> in addition
to C<http>.

=cut

use constant USE_LOCAL_DNS_DCV => 0;

#----------------------------------------------------------------------

=head2 MAX_DOMAINS_PER_CERTIFICATE()

A limit on the number of domains to request per certificate. This will
depend on the external CA’s own restrictions. If a provider module sets
no limit, AutoSSL will assume that the CA allows infinitely many domains on
a single certificate--which is probably not accurate!

=cut

sub MAX_DOMAINS_PER_CERTIFICATE { return undef }

#----------------------------------------------------------------------

=head2 PROPERTIES()

Returns a list of key/value pairs that define additional
properties for this provider module. At present, the value C<terms_of_service>
defines a URL that, if present, the API caller will need to accept in order to
enable the module. (That acceptance is indicated by submitting this value as
C<terms_of_service_accepted>.)

=cut

sub PROPERTIES { }

#----------------------------------------------------------------------

=head2 EXPORT_PROPERTIES( NAME1 => VALUE1, NAME2 => VALUE2, ... )

A means of sending information to an
external provider … such as registration data.

=cut

sub EXPORT_PROPERTIES { ... }

#----------------------------------------------------------------------

=head2 RESET()

Resets the server’s registration with the remote provider.
(This could be as simple as deleting the local file that stores the
registration data.)

=cut

sub RESET { ... }

#----------------------------------------------------------------------

=head2 CERTIFICATE_IS_FROM_HERE( PEM_STRING )

Indicates whether the certificate comes from this provider.
The means of doing this determination will vary depending on the CA
and the specific certificate issued.

If the subclass doesn’t define this method, AutoSSL assumes that
nothing comes from this module.

=cut

sub CERTIFICATE_IS_FROM_HERE { return undef }

=head2 CERTIFICATE_PARSE_IS_FROM_HERE( C<Cpanel::SSL::Object::Certificate>->parsed() )

The provider module can optionally implement a
CERTIFICATE_PARSE_IS_FROM_HERE which much return
the same output CERTIFICATE_IS_FROM_HERE when passed
in the pre-parsed PEM_STRING.

This avoids the need to reparse the certificate.

=cut

#----------------------------------------------------------------------

=head2 DISPLAY_NAME()

A name for the provider module meant for display in an end-user interface.
This name can be free-form text, whereas module names must comply
with Perl’s namespacing conventions (e.g., no colons, spaces, etc.).

=cut

sub DISPLAY_NAME {
    my ($self) = @_;

    my $class = ref($self) || $self;

    return ( $class =~ s<.+::><>r );
}

#----------------------------------------------------------------------

=head2 MODULE_NAME()

The name of the module.  This should not be different from the name
of the .pm file.

=cut

sub MODULE_NAME {
    my ($self) = @_;
    return $self->_module_name();
}

#----------------------------------------------------------------------

=head2 HTTP_DCV_MAX_REDIRECTS()

The number of redirects that the Certificate Authority will permit during
a DCV check. The default is 5.

=cut

#NB: 5 is HTTP::Tiny’s default as of v0.058 of that module.
sub HTTP_DCV_MAX_REDIRECTS { return 5 }

#----------------------------------------------------------------------

=head2 SPECS

A set of attributes that AutoSSL itself doesn’t need but that help
an administrator to compare AutoSSL providers.

This should be a list of key/value pairs; the following values are
recognized and used in WHM:

=over

=item * C<DELIVERY_METHOD> - Either C<api> (immediate delivery) or C<queue>.

=item * C<AVERAGE_DELIVERY_TIME> - in seconds

=item * C<VALIDITY_PERIOD> - in seconds

=item * C<RATE_LIMIT_CERTIFICATES_PER_REGISTERED_DOMAIN_PER_WEEK> - If the
provider imposes a weekly rate limit on the number of certificates issued per
registered domain, give that number here. For example, as of March 2020
L<Let’s Encrypt|https://letsencrypt.org/docs/rate-limits/> imposes a limit
of 50 certificates per registered domain per week.

=back

=cut

use constant SPECS => ();

#----------------------------------------------------------------------

=head2 ON_ACCOUNT_RENAME( OLDNAME, NEWNAME )

Logic to execute after account rename. Useful to clean up
anything a provider may track by username (e.g., the cPanel provider’s
pending queue).

(It was formerly documented that these functions should return the number
of user accounts modified—i.e., 0 or 1—but that doesn’t seem to make
sense or to have been used.)

=cut

use constant ON_ACCOUNT_RENAME => 0;

=head2 ON_ACCOUNT_TERMINATION( USERNAME )

Similar to C<ON_ACCOUNT_RENAME()> but for account termination.

=cut

*ON_ACCOUNT_TERMINATION = *ON_ACCOUNT_RENAME;

=head2 ON_DOMAIN_REMOVAL( OLDNAME, NEWNAME )

Similar to C<ON_ACCOUNT_RENAME()> but for domain removal.

=cut

*ON_DOMAIN_REMOVAL = *ON_ACCOUNT_RENAME;

=head2 ON_START_CHECK()

Similar to C<ON_ACCOUNT_RENAME()> but for the start of an AutoSSL check.

=cut

*ON_START_CHECK = *ON_ACCOUNT_RENAME;

=head2 ON_FINISH_CHECK()

Similar to C<ON_START_CHECK()> but for the full end of an AutoSSL check,
i.e., when all domains for all users were processed.

=cut

*ON_FINISH_CHECK = *ON_ACCOUNT_RENAME;

#----------------------------------------------------------------------

=head2 SORT_VHOST_FQDNS( USERNAME, FQDN1, FQDN2, .. )

Returns the given FQDNs, sorted.

NOTE: This function assumes that all of the FQDNs resolve to the same
virtual host. This sort order ensures that the system adds the domains that
users will most likely visit to the certificate first.

B<IMPORTANT:> This function also B<REQUIRES> that each FQDN given to it be
a B<literal> member of the vhost. Wildcard-reducer domains will break this
function. To get a properly-sorted list of wildcard-reduced domains for
a given vhost, sort the vhost’s own domains, then reduce the result of
that sort.

The default sort algorithm prioritizes domains in the following order:

=over 4

=item 1) Any FQDNs that the virtual host’s current SSL certificate secures

=item 2) The primary domain on the cPanel account and then its C<www.> and
C<mail.> subdomains.

=item 3) Each addon domain followed by its “www.” and “mail.” subdomains.
For example:

A cPanel user called C<example> (whose primary domain is C<example.com>)
creates an addon domain called C<foo.com>. This addon domain, like all
cPanel addon domains, exists on a separate virtual host. (In this example,
the new virtual host name would be C<foo.example.com>). The system prioritizes
C<foo.com> over C<foo.example.com>.

=item 4) Domains with fewer dots. (e.g., prioritize C<foo.com>
ahead of C<www.foo.com>)

=item 5) Subdomains: C<www>, C<mail>, C<whm> (if reseller), C<webmail>,
C<cpanel>, C<autodiscover>, C<webdisk>

=item 6) Shorter domains

=item 7) Apply lexicographical sort

=back

=cut

sub SORT_VHOST_FQDNS {
    my ( $self, $username, @fqdns ) = @_;

    Cpanel::Context::must_be_list();

    # Single-domain sets don’t need sorting.
    return @fqdns if 1 == @fqdns;

    require Cpanel::Config::WebVhosts;

    #Cache this so that a user with 100s of vhosts doesn’t load
    #the same file 100s of times per AutoSSL run.
    #
    #TODO: Provide a deeper-level cache of this object, perhaps
    #in C::C::WebVhosts itself. We’ve likely already loaded the
    #object at least once to get to here anyway.
    my $vh_conf = $self->{'_vhconf'}{$username} ||= Cpanel::Config::WebVhosts->load($username);

    my $pri_domain = $vh_conf->main_domain();

    my $vh_servername = $vh_conf->get_vhost_name_for_domain( $fqdns[0] );

    #In case $fqdns[0] is a service (formerly proxy) subdomain.
    $vh_servername ||= $vh_conf->get_vhost_name_for_ssl_proxy_subdomain( $fqdns[0] );

    if ( !$vh_servername ) {
        die Cpanel::Exception->create( "“[_1]” does not own a domain named “[_2]” on this server.", [ $username, $fqdns[0] ] );
    }

    my $is_reseller = $self->{'_is_reseller'}{$username} //= do {
        require Whostmgr::Resellers::Check;
        Whostmgr::Resellers::Check::is_reseller($username) || 0;
    };

    my $has_ssl_cr;

    # This will break if we ever have a domain set that isn’t
    # a vhost that has multiple domains. As of v92 that’s not
    # a problem, though.
    if ( Cpanel::Apache::TLS->has_tls($vh_servername) ) {
        try {
            require Cpanel::SSL::Objects::Certificate::File;
            my $cert_path = Cpanel::Apache::TLS->get_certificates_path($vh_servername);
            my $cert_obj  = Cpanel::SSL::Objects::Certificate::File->new( path => $cert_path );
            $has_ssl_cr = sub {
                $cert_obj->valid_for_domain(shift);
            };
        }
        catch {
            local $@ = $_;
            warn;
        };
    }

    #Getting the domains from vhost config (userdata) is better than
    #getting them from the cpuser file because the cpuser file can contain
    #DNS zones that aren’t in web vhosts (if the owning reseller has
    #added them).
    my %domains_lookup = map { $_ => 1 } @{ $vh_conf->all_created_domains_ar() };

    my @proxy_sdoms = (
        'www',
        'mail',
        'webmail',
        'cpanel',
        ( $is_reseller ? 'whm' : () ),
        'autodiscover',
        'webdisk'
    );

    my $proxy_sdom_re_txt = join( '|', @proxy_sdoms );
    my $proxy_sdom_re     = qr<($proxy_sdom_re_txt)>;

    my $get_lead_sub_cr = sub {
        my ($domain) = @_;

        #Make sure the domain isn’t itself a created domain.
        #This is important for cases such as where the user
        #created a “mail.” subdomain prior to cP/WHM v60, when we
        #started putting that FQDN onto vhosts automatically.
        if ( !exists $domains_lookup{$domain} ) {

            #The “meat” of this function:
            #If the first part of the FQDN is a service (formerly proxy) subdomain,
            #and if the rest is a cpuser domain, then return the
            #service (formerly proxy) subdomain.
            my ( $sub, $rest ) = split m<\.>, $domain, 2;
            if ( exists $domains_lookup{$rest} && grep { $_ eq $sub } @proxy_sdoms ) {
                return $sub;
            }
        }

        return q<>;
    };

    #Higher priority means a *higher* value. This means we have to
    #sort descending. It also allows any subdomain not in the list to
    #be given a value of 0, which will thus sort last.
    my %proxy_sdom_rank = map { ( reverse @proxy_sdoms )[$_] => 1 + $_ } 0 .. $#proxy_sdoms;

    my @sorts = do {

        # See Cpanel::Sort::Multi for an explanation about this
        # unfortunate syntax
        package Cpanel::Sort::Multi;
        #
        # 64 is the max commonName length.  64 is inlined
        # due to the unfortunate syntax
        #
        # RFC3280 limits the commonName to 64 bytes.
        #
        # We want to put anything longer than 64 further down
        # the domain list because the first domain is used
        # in the commonName field which has the lower limit
        #
        my @ss = ( sub { ( length $a > 64 ) <=> ( length $b > 64 ) } );

        #Give first priority to domains that already have SSL.
        if ($has_ssl_cr) {
            push @ss, sub { $has_ssl_cr->($b) <=> $has_ssl_cr->($a) };
        }

        #Next, the account’s primary domain and its www subdomain.
        #Only relevant if the vhost is the account’s primary one.
        if ( $vh_servername eq $pri_domain ) {
            push @ss, sub { ( $b eq $vh_servername ) cmp( $a eq $vh_servername ) };
            push @ss, sub { ( $b eq "www.$vh_servername" ) cmp( $a eq "www.$vh_servername" ) };
            push @ss, sub { ( $b eq "mail.$vh_servername" ) cmp( $a eq "mail.$vh_servername" ) };
        }

        #Now prioritize FQDNs that are NOT the vhost’s servername
        #nor a subdomain thereof.
        #Since we already prioritized the account’s primary domain,
        #this prioritizes addons above subdomains.
        #Only relevant if the vhost is NOT the account’s primary.
        else {
            my $vh_sn_re = qr<\A ( (?:$proxy_sdom_re_txt) \. )? \Q$vh_servername\E\z>x;
            push @ss, sub {
                ( $a =~ $vh_sn_re ) cmp( $b =~ $vh_sn_re );
            };
        }

        push @ss, (

            #Prioritize an FQDN with fewer dots
            sub { ( $a =~ tr<.><> ) <=> ( $b =~ tr<.><> ) },

            #Now we prioritize the auto-created subdomains,
            #in the order of “importance” as given above.
            sub {
                ( $proxy_sdom_rank{ $get_lead_sub_cr->($b) } || 0 ) <=> ( $proxy_sdom_rank{ $get_lead_sub_cr->($a) } || 0 );
            },

            #Then, prioritize shorter length
            sub { length($a) <=> length($b) },

            #If we get here, then just to get a predictable result,
            #sort lexicographically.
            sub { $a cmp $b },
        );

        @ss;
    };

    return Cpanel::Sort::Multi::apply( \@sorts, @fqdns );
}

=head2 get_vhost_dcv_errors( $DCV_OBJECT )

This optional method allows a provider to do Domain Control Validation (DCV)
as part of the AutoSSL vhost processing rather than during certificate orders
(i.e., during C<renew_ssl()>). Defining C<get_vhost_dcv_errors()> can mitigate
certain issues that arise if, for some reason, cPanel & WHM’s local DCV
succeeds but the provider/CA’s DCV fails.

For example: Assume local DCV passes domains A, B, & C, but the provider’s
DCV passes only A & B. The resulting certificate will include A & B. The
next time AutoSSL runs, it’ll see that A & B certificate as incomplete,
so it’ll do local DCV and again pass domains A, B, & C. If the provider
furnishes a C<get_vhost_dcv_errors()> method, then at this point AutoSSL
will run that function see that only A & B pass the provider’s DCV, and so
AutoSSL will know to forgo requesting another certificate since it would
cover the same set of domains as the current certificate. Without
C<get_vhost_dcv_errors()>, AutoSSL will tell C<renew_ssl()> to request a
certificate for A, B, & C, and the provider will reduce that to A & B
after its DCV, B<BUT!> the provider won’t know that A & B matches the
currently-installed certificate, so it’ll request a new certificate,
unaware that it’s just going to be a duplicate of the already-installed
certficate. So we’ll end up requesting identical certificate after identical
certificate, which at best is just extra work but at worst will prematurely
trip one of the CA’s rate limits (as happened with Let’s Encrypt prior to the
creation of this function).

$DCV_OBJECT is an instance of L<Cpanel::SSL::Auto::ProviderDCV>.

Note that the set of domains in $DCV_OBJECT will be the full set of
AutoSSL-eligible domains, B<NOT> subject to C<MAX_DOMAINS_PER_CERTIFICATE()>.
Consider if C<MAX_DOMAINS_PER_CERTIFICATE()> were 20, and a vhost had 30
domains. We’d DCV 20 domains, chosen as per C<SORT_VHOST_FQDNS()>. If any
of those DCVs fail, to make optimal use of the certificate we should then
DCV additional domains (out of the 10 excluded from the first DCV batch)
to maximize the number of domains on the certificate—and, thus, SSL coverage.

There is no return.

NB: This function used to be called C<get_dcv_errors()>. It was renamed
in v84 to clarify that it’s called for one vhost at a time. At the time
of this rename, only two AutoSSL providers (cPanel/Sectigo and Let’s Encrypt)
were known to be in production use, and cPanel maintains both of them. Since
v84 also switched from the “cpanel-letsencrypt” plugin to the new
“cpanel-letsencrypt-v2”, it was an opportune time to do this rename.

=head3 Wildcard Reduction

As of v88, AutoSSL implements “wildcard reduction”: where possible, AutoSSL
will secure multiple “sibling” domains via a single wildcard domain rather
than the individual domains. If a wildcard fails DCV, AutoSSL will reattempt
DCV on the same vhost but with the DCV-failed wildcards replaced with the
domains for which the wildcard had substituted. Thus, the same vhost may now
receive multiple C<get_vhost_dcv_errors()> calls, with latter invocations
receiving domains that had previously passed DCV.

Wildcard reduction also applies in the case where “sibling” domains straddle
multiple vhosts—the gain being that we only DCV 1 domain as opposed to 2+.
Thus, the same wildcard may be passed multiple times to
C<get_vhost_dcv_errors()> since that wildcard may apply to multiple vhosts.

AutoSSL providers need to accommodate such “redundant” DCV operations.

=cut

#----------------------------------------------------------------------

=head2 $yn = is_obsolete()

Returns a boolean that indicates this provider is obsolete. Should be overridden
by a subclassed obsolete provider to return true. An obsolete provider should
(generally) not appear in AutoSSL-related API or UI output and should not issue
new certificates, but may exist to recognize certificates that were issued
before the provider became obsolete.

=cut

use constant is_obsolete => 0;

#----------------------------------------------------------------------

=head1 INHERITED METHODS

These methods should not be overridden and can be called from within
a subclass’s logic.

=head2 $yn = is_all_users()

Returns a boolean that indicates whether the class instantiation
indicated an all-users AutoSSL instance. If the instantiation
did not include a C<user_mode>, this will throw an exception.

=cut

sub is_all_users ($self) {
    die 'No “user_mode” was set on object instantiation!' if !$self->{'user_mode'};

    return 'all' eq $self->{'user_mode'};
}

=head2 start_logging( USERNAME )

C<USERNAME> is the username for whom we are logging. This doesn’t
change functionality; it’s just a reporting convenience. If
!length C<USERNAME>, the logger records that this log is of an AutoSSL
run for all users.

=cut

sub start_logging {
    my ( $self, $username ) = @_;

    return $self->_create_logger(
        provider => scalar( ( ref $self )->_module_name() ),
        username => $username,
    );
}

=head2 resume_logging( START_TIME )

C<START_TIME> is an ISO 8601 time and indicates a log to
append to. If a log for this provider with the given start time doesn’t
exist, an exception is thrown.)

This method returns the object itself, which facilitates the following
convenience:

    my $pobj = Cpanel::SSL::Auto::Provider::Blah->new()->start_logging();

=cut

sub resume_logging {
    my ( $self, $start_time ) = @_;

    if ( !$start_time ) {
        die 'start time required for resume_logging()!';
    }

    return $self->_create_logger(
        start_time => $start_time,
    );
}

=head2 log( LEVEL, MESSAGE )

C<MESSAGE> is free-form text. C<LEVEL> can be one of:

=over 4

=item * C<success>

=item * C<info>

=item * C<warn>

=item * C<error>

=back

=cut

sub log {
    my ( $self, $level, $message ) = @_;

    if ( !$self->{'_logger'} ) {
        die "Must start_logging() first! ($level: $message)";
    }

    return $self->{'_logger'}->$level($message);
}

=head2 get_log_start_time()

Returns the time (ISO 8601 format) at which this class instance started
logging. If there is no logging for this instance, returns undef.

=cut

sub get_log_start_time {
    my ($self) = @_;

    return $self->{'_logger'} && $self->{'_logger'}->get_start_time();
}

=head2 keep_log_in_progress()

This creates an C<in_progress> flag that indicates that an AutoSSL run still
has work left to do after its initial run.

=cut

sub keep_log_in_progress {
    my ($self) = @_;

    $self->{'_set_to_in_progress'} ||= $self->{'_logger'}->set_in_progress();

    $self->{'_keep_log_in_progress'} = 1;

    return;
}

=head2 $type = I<OBJ>->get_user_default_key_type( $USERNAME )

Returns a user’s default key type. This applies a cache to avoid
reopening the user’s cpuser file on subsequent lookups.

=cut

sub get_user_default_key_type ( $self, $username ) {
    return $self->{'_user_key_type'}{$username} ||= do {
        local ( $@, $! );
        require Cpanel::SSL::DefaultKey::User;

        Cpanel::SSL::DefaultKey::User::get($username);
    };
}

=head2 $pem = I<OBJ>->generate_key( $USERNAME )

Returns a newly-generated key in PEM format. The key will match
the user’s preference for SSL key generation (e.g., RSA vs. ECDSA).

=cut

sub generate_key ( $self, $username ) {
    local ( $@, $! );
    require Cpanel::SSL::Create;

    my $key_type = $self->get_user_default_key_type($username);

    return Cpanel::SSL::Create::key($key_type);
}

=head2 handle_new_certificate( %OPTS )

Responds to the availability of a new certificate for a given
domain set. For example, if the domain set is a web vhost, this function
will install the certificate; if the domain set is dynamic DNS, then
this function will notify the user as needed.

This encompasses the logic formerly found in the C<install_certificate()>
method (which no longer exists as of v92).

%OPTS are:

=over

=item * C<domain_set_name>: The name of the domain set to which
the certificate pertains. (See L<Cpanel::SSL::Auto::Run::DomainSet>
for more information about domain sets.)

=item * C<username>: The user who owns the given C<domain_set_name>.
If the user does not have such permission an exception will be thrown.
(This parameter was optional prior to v92.)

For web vhosts, see the UAPI call
C<WebVhosts::list_vhosts()> for more information on virtual host names.

=item * C<certificate_pem>: The certificate, PEM-encoded

=item * C<key_pem>: The key, PEM-encoded

=item * C<cab_pem>: OPTIONAL, the CA bundle, PEM-encoded. (Separate
certificates with a newline.)

=back

This returns a boolean that indicates whether the handling “succeeded”.
“Success” in this case merely means that a retry of the handling should
B<NOT> happen; for example, if the input was invalid, a failure will be
reported to the log, though the function’s return will indicate
“success”—i.e., “don’t do that again, please.”

You should use this method rather than an API call to handle new
certificates because:

=over

=item * It relieves the caller of the need to worry about the type
of domain set (e.g., web vhost, dynamic DNS, ..).

=item * It’s faster than an API call because it doesn’t
C<fork()>/C<exec()>.

=item * When called from within C<autossl_check>’s call into
C<renew_ssl()>, it won’t restart Apache and Dovecot
for each certificate installation, which the API call always does.

=back

=cut

#NOTE: This method references code that is only
#available from within a cPanel binary.
sub handle_new_certificate {
    my ( $self, %opts ) = @_;

    my @MUST_BE_LOADED_TO_INSTALL = (
        'Cpanel::SSLInstall',
    );

    my @not_loaded = grep { !Cpanel::LoadModule::Utils::module_is_loaded($_) } @MUST_BE_LOADED_TO_INSTALL;

    if (@not_loaded) {

        # Should never happen, but just in case:
        die "Must be loaded to handle_new_certificate(): @not_loaded";
    }

    #----------------------------------------------------------------------

    #Require the key for AutoSSL because we haven’t saved it
    #in the account yet.
    my @missing = grep { !length $opts{$_} } qw(
      certificate_pem
      key_pem
      domain_set_name
      username
    );

    if (@missing) {
        die "handle_new_certificate() - missing: @missing";
    }

    my $start_msg;
    my $todo_cr;

    require Cpanel::Config::userdata::Load;

    my $failed;

    if ( Cpanel::Config::userdata::Load::user_has_domain( @opts{ 'username', 'domain_set_name' } ) ) {
        $start_msg = locale()->maketext( 'Installing “[_1]”’s new certificate …', $opts{'domain_set_name'} );

        $todo_cr = sub {

            # _install_certificate() logs a warning for
            # failure cases. Use the boolean return as an
            # indicator of success/failure.
            $failed = !$self->_install_certificate(%opts);
            $self->log( 'success', locale()->maketext('Success!') );
        };
    }
    else {
        my $ddns_lookup = $self->_get_ddns_lookup( $opts{'username'} );

        if ( exists $ddns_lookup->{ $opts{'domain_set_name'} } ) {
            $start_msg = locale()->maketext( 'The system will notify “[_1]” of “[_2]”’s new certificate.', @opts{ 'username', 'domain_set_name' } );

            require Cpanel::SSL::Auto::DynamicDNS;

            $todo_cr = sub {
                Cpanel::SSL::Auto::DynamicDNS::save_and_enqueue_notification(
                    @opts{ 'username', 'domain_set_name', 'key_pem', 'certificate_pem' },
                );
            };
        }
        else {

            # This shouldn’t happen normally, so leave it untranslated:
            $self->log( 'error', "Bad domain set name for user “$opts{'username'}”: $opts{'domain_set_name'}" );
        }
    }

    if ($todo_cr) {
        $self->log( 'info', $start_msg );

        my $indent = $self->create_log_level_indent();

        try {
            $todo_cr->();
        }
        catch {
            $failed = 1;
            $self->log( 'error', $_ );
        };
    }

    return !$failed;
}

sub _get_ddns_lookup ( $self, $username ) {
    my $can_use_cache = $self->{'_last_ddns_user'};
    $can_use_cache &&= $self->{'_last_ddns_user'} eq $username;

    if ( !$can_use_cache ) {
        require Cpanel::WebCalls::Datastore::Read;
        my $id_entry = Cpanel::WebCalls::Datastore::Read->read_for_user($username);
        my @ddns     = grep { $_->isa('Cpanel::WebCalls::Entry::DynamicDNS') } values %$id_entry;

        my %lookup;
        @lookup{ map { $_->domain() } @ddns } = ();

        $self->{'_last_ddns_user'} = $username;
        $self->{'_last_ddns'}      = \%lookup;
    }

    return $self->{'_last_ddns'};
}

sub _install_certificate ( $self, %opts ) {

    my ( $added_domains_ar, $missing_domains_ar ) = $self->_get_website_added_and_missing_domains( @opts{ 'username', 'domain_set_name', 'certificate_pem' } );

    require Whostmgr::ACLS;

    #Needed for Cpanel::SSLInstall to be happy.
    local $ENV{'REMOTE_USER'} = 'root';
    local %Whostmgr::ACLS::ACL;
    Whostmgr::ACLS::init_acls();

    _do_hook( \%opts, 'AutoSSL::installssl', 'pre' );

    my $install = $self->_installssl(
        domain          => $opts{'domain_set_name'},
        key             => $opts{'key_pem'},
        crt             => $opts{'certificate_pem'},
        cab             => $opts{'cab_pem'},
        installing_user => $opts{'username'},
    );

    if ( $install->{'status'} ) {
        _dispatch_install_notification(
            %opts,
            missing_domains => $missing_domains_ar,
            added_domains   => $added_domains_ar,
        );
    }
    else {

        # If the message changes in Cpanel::SSLInstall this check needs to be updated
        if (   index( $install->{'message'}, 'do not control a domain' ) > -1
            || index( $install->{'message'}, 'controls a domain with that name' ) > -1 ) {
            die Cpanel::Exception::create( 'DomainOwnership', 'The account “[_1]” does not own the domain “[_2]”.', [ $opts{'username'}, $opts{'domain_set_name'} ] );
        }

        die Cpanel::Exception->create( 'The system failed to install an [asis,SSL] certificate onto the website “[_1]” because of the following error: [_2]', [ $opts{'domain_set_name'}, $install->{'message'} ] );
    }

    _do_hook( \%opts, 'AutoSSL::installssl', 'post' );

    return $install->{'status'};
}

# Only declare a domain missing
# if it is not ssl capable and the previous cert
# was not self signed as a self signed does not constitute 'coverage'
#
# This ensure that domains that have been removed
# from the account do not trigger the CertificateInstalledReducedCoverage
# notification.
sub _certificate_should_report_missing_domains {
    my ($cert_obj) = @_;

    return !$cert_obj->is_self_signed();
}

#NB: this is tested directly
#
# This takes the $web_vhost_name and the $new_certificate_pem
# and compares it against the existing installed certificate
# and webvhost data (userdata) to determine which vhost domains
# the new certificate newly secures or doesn’t secure.
#
# We define “missing” as: not secured via the new certificate
# but previously secured via the old certificate and currently
# existing in the webvhost data. (It may be better to call these
# “lost” domains instead.)
#
# Note the accommodation of wildcard domains: we can’t merely check
# whether a certificate explicitly includes a given domain; we have
# to check for the more generic case of whether the certificate “secures”
# the domain, which can happen via either explicit inclusion or a
# wildcard domain.
#
sub _get_website_added_and_missing_domains {
    my ( $self, $username, $web_vhost_name, $new_certificate_pem ) = @_;

    my ( @added_domains, @missing_domains );

    require Cpanel::SSL::Objects::Certificate;
    my $new_cert_obj = Cpanel::SSL::Objects::Certificate->new(
        cert => $new_certificate_pem,
    );

    require Cpanel::SSL::Objects::Certificate::File;
    my $old_certs_path = Cpanel::Apache::TLS->get_certificates_path($web_vhost_name);
    my $old_cert_obj   = Cpanel::SSL::Objects::Certificate::File->new_if_exists(
        path => $old_certs_path,
    );

    if ($old_cert_obj) {

        require Cpanel::AcctUtils::DomainOwner::Tiny;
        my $user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $web_vhost_name, { default => 'nobody' } );

        if ( $username && ( $user ne $username ) ) {
            die "Vhost “$web_vhost_name” belongs to “$user”, not to “$username”!";
        }

        require Cpanel::WebVhosts;
        my @ssl_capable_domains = map { $_->{'domain'} } Cpanel::WebVhosts::list_ssl_capable_domains( $user, $web_vhost_name );

        my $old_domains_ar = $old_cert_obj->domains();
        my $new_domains_ar = $new_cert_obj->domains();

        require Cpanel::SSL::Utils;

        my $old_secured_ar = Cpanel::SSL::Utils::find_domains_lists_matches(
            $old_domains_ar,
            \@ssl_capable_domains,
        );
        my $new_secured_ar = Cpanel::SSL::Utils::find_domains_lists_matches(
            $new_domains_ar,
            \@ssl_capable_domains,
        );

        if ( _certificate_should_report_missing_domains($old_cert_obj) ) {
            my @ssl_unsecured_domains = Cpanel::Set::difference(
                \@ssl_capable_domains,
                $new_secured_ar,
            );

            my $not_missing_ar = $new_cert_obj->domains();
            push @$not_missing_ar, _get_excluded_for_user($user);

            @missing_domains = Cpanel::Set::difference(
                \@ssl_unsecured_domains,
                $not_missing_ar,
            );
        }

        @added_domains = Cpanel::Set::difference(
            $new_secured_ar,
            $old_secured_ar,
        );
    }
    else {
        @added_domains = @{ $new_cert_obj->domains() };
    }

    return ( \@added_domains, \@missing_domains );
}

sub _get_excluded_for_user {
    my ($username) = @_;

    my @ret;

    #We don’t consider domains that the user
    #has excluded to be “missing”.
    if ($username) {
        require Cpanel::SSL::Auto::Exclude::Get;
        try {
            @ret = Cpanel::SSL::Auto::Exclude::Get::get_user_excluded_domains($username);
        }
        catch {
            warn "Failed to read “$username”’s excluded AutoSSL domains: $_";
        };
    }

    return @ret;
}

#overridden in tests
sub _installssl {
    shift;

    #We just checked on whether this module is loaded or not above.
    goto 'Cpanel::SSLInstall'->can('real_installssl');    # PPI NO PARSE
}

=head2 new( %OPTS )

Constructor. %OPTS are:

=over

=item * C<user_mode> - C<all> or C<single>.

=back

=cut

sub new ( $class, %OPTS ) {

    if ( $OPTS{'user_mode'} && !grep { $_ eq $OPTS{'user_mode'} } qw( all single ) ) {
        die "Invalid “user_mode”: “$OPTS{'user_mode'}”";
    }

    return bless \%OPTS, $class;
}

#----------------------------------------------------------------------

#This should not be called from subclasses
sub asked_to_keep_log_in_progress {
    my ($self) = @_;
    return $self->{'_keep_log_in_progress'} ? 1 : 0;
}

#Nor this.
sub set_log_completed {
    my ($self) = @_;

    $self->{'_logger'}->set_completed();

    return;
}

#Nor this.
sub DAYS_TO_NOTIFY {
    my ($self) = @_;

    return $self->DAYS_TO_REPLACE() / 2;
}

#Nor this.
sub DAYS_TO_NOTIFY_AFTER_EXPIRE {
    my ($self) = @_;

    return 3;
}

#Nor this.
sub clear_user_caches {
    my ( $self, $username ) = @_;

    delete $self->{'_vhconf'}{$username};

    return;
}

#----------------------------------------------------------------------

sub _create_logger {
    my ( $self, %OPTS ) = @_;

    if ( $self->{'_logger'} ) {
        die "Already logging!";    #shouldn’t happen
    }

    if ( $LOGGER_CLASS eq 'Cpanel::SSL::Auto::Log' && !$INC{'Cpanel/SSL/Auto/Log.pm'} ) {
        Cpanel::LoadModule::load_perl_module($LOGGER_CLASS);
    }
    $self->{'_logger'} = $LOGGER_CLASS->new(%OPTS);

    return $self;
}

sub _module_name {
    my ($class) = @_;

    my $pkg = __PACKAGE__;
    $class =~ m<\A\Q$pkg\E::([^:=]+)> or die "Invalid AutoSSL provider module: “$class”!";

    return $1;
}

my %CLASS_NOTIFY_KEY = (
    CertificateInstalledReducedCoverage  => 'notify_autossl_renewal_coverage_reduced',
    CertificateInstalledUncoveredDomains => 'notify_autossl_renewal_uncovered_domains',
    CertificateInstalled                 => 'notify_autossl_renewal',
);

#NB: this is tested directly
sub _dispatch_install_notification {
    my (%opts) = @_;

    my $vhost_name = $opts{'domain_set_name'};
    my $user       = $opts{'username'};
    my $cert_pem   = $opts{'certificate_pem'};
    my $key_pem    = $opts{'key_pem'};

    my @class_specific_notify_opts;

    my $class;

    if ( @{ $opts{'missing_domains'} } ) {
        $class = 'CertificateInstalledReducedCoverage';

        push @class_specific_notify_opts, (
            missing_domains => $opts{'missing_domains'},
        );
    }
    else {
        if ($user) {
            my @vhost_domains = Cpanel::WebVhosts::list_ssl_capable_domains( $user, $vhost_name );
            $_ = $_->{'domain'} for @vhost_domains;
            if ( !@vhost_domains ) {
                die "User “$user” does not own a vhost named “$vhost_name”!";
            }

            require Cpanel::SSL::Objects::Certificate;
            my $cert_obj = Cpanel::SSL::Objects::Certificate->new( cert => $cert_pem );

            #Domains that are on the certificate or that we’re excluding are,
            #by definition, not “uncovered”, so let’s not consider those to
            #justify sending an UncoveredDomains notice.
            my $not_uncovered_domains_ar = $cert_obj->domains();
            push @$not_uncovered_domains_ar, _get_excluded_for_user($user);

            my @uncovered = Cpanel::Set::difference(
                \@vhost_domains,
                $not_uncovered_domains_ar,
            );

            if (@uncovered) {

                require Cpanel::WildcardDomain::Tiny;
                my @wildcard_domains = grep { Cpanel::WildcardDomain::Tiny::is_wildcard_domain($_) } @{ $cert_obj->domains() };

                if (@wildcard_domains) {
                    require Cpanel::SSL::Auto::Wildcard;
                    @uncovered = Cpanel::SSL::Auto::Wildcard::reduce_domains_by_wildcards( \@uncovered, @wildcard_domains );

                    @uncovered = Cpanel::Set::difference(
                        \@uncovered,
                        \@wildcard_domains,
                    );
                }

                if (@uncovered) {
                    $class = 'CertificateInstalledUncoveredDomains';

                    push @class_specific_notify_opts, (
                        uncovered_domains => \@uncovered,
                    );
                }
            }
        }

        $class ||= 'CertificateInstalled';
    }

    my $notify_key = $CLASS_NOTIFY_KEY{$class} or die "No key for $class!";

    return 0 if !_get_autossl_config_metadata()->{$notify_key};

    if ( !$user ) {
        my $err;
        try {
            $user = Cpanel::Domain::Owner::get_owner_or_die($vhost_name);
        }
        catch {
            $err = $_;
            my $error_as_string = Cpanel::Exception::get_string($err);
            Cpanel::Debug::log_warn("The AutoSSL install notification could not be dispatched because the system could not determine user for the vhost “$vhost_name”: $error_as_string");
        };
        return if $err;
    }

    #These notices go to both the admin and the user.
    for my $target (qw(admin user)) {
        if ( $target eq 'user' ) {
            require Cpanel::ContactInfo;
            my $cinfo = Cpanel::ContactInfo::get_contactinfo_for_user($user);

            next if !$cinfo->{$notify_key};
        }

        require Cpanel::SSLStorage::Utils;
        my ( $key_ok, $key_id ) = Cpanel::SSLStorage::Utils::make_key_id($key_pem);

        require Cpanel::Notify::Deferred;
        require Cpanel::IP::Remote;

        Cpanel::Notify::Deferred::notify(
            'class'            => "AutoSSL::$class",
            'application'      => "AutoSSL::$class",
            'constructor_args' => [
                _get_icontact_args_for_target_and_user( $target, $user ),
                'key_id'          => $key_id,
                vhost_name        => $vhost_name,
                origin            => "AutoSSL",
                source_ip_address => Cpanel::IP::Remote::get_current_remote_ip(),
                added_domains     => $opts{'added_domains'},

                @class_specific_notify_opts,
            ]
        );
    }

    return;
}

# copied from scripts/notify_expiring_certificates
#XXX UGLY refactor/normalize
sub _get_icontact_args_for_target_and_user {
    my ( $target, $user ) = @_;

    if ( $target eq 'user' ) {
        return (
            user                              => $user,
            username                          => $user,
            to                                => $user,
            notification_targets_user_account => 1,
        );
    }

    return (
        username => $user,

    );
}

our $_autossl_config_metadata;

sub _get_autossl_config_metadata {
    require Cpanel::SSL::Auto::Config::Read;
    return ( $_autossl_config_metadata ||= Cpanel::SSL::Auto::Config::Read->new()->get_metadata() );
}

sub _do_hook {
    my ( $args, $event, $stage ) = @_;

    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => $event,
            'stage'    => $stage,
        },
        $args,
    );

    return 1;
}
1;
