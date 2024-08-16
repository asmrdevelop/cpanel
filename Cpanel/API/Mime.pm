package Cpanel::API::Mime;

# cpanel - Cpanel/API/Mime.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                               ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::AdminBin::Serializer         ();
use Cpanel::ArrayFunc::Uniq              ();
use Cpanel::CachedCommand::Utils         ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Config::userdata::Load ();
use Cpanel::DomainLookup           ();
use Cpanel::Encoder::Tiny          ();
use Cpanel::Encoder::URI           ();
use Cpanel::Exception              ();
use Cpanel::FileUtils::TouchFile   ();
use Cpanel::FileUtils::Write       ();
use Cpanel::HttpUtils::Htaccess    ();
use Cpanel::SafeDir::Fixup         ();
use Cpanel::StringFunc::Case       ();

=head1 MODULE

C<Cpanel::API::Mime>

=head1 DESCRIPTION

C<Cpanel::API::Mime> provides API calls related to mime types, redirects, handlers and hotlinks.
These are all managed via .htaccess files.

=head1 FUNCTIONS

=cut

my $mime_feature      = { needs_feature => "mime" };
my $handlers_feature  = { needs_feature => "handlers" };
my $hotlink_feature   = { needs_feature => "hotlink" };
my $redirects_feature = { needs_feature => "redirects" };
my $allow_demo        = { allow_demo    => 1 };

our %API = (
    _needs_role     => 'WebServer',
    list_mime       => $allow_demo,
    add_mime        => $mime_feature,
    delete_mime     => $mime_feature,
    list_handlers   => $allow_demo,
    add_handler     => $handlers_feature,
    delete_handler  => $handlers_feature,
    list_redirects  => $redirects_feature,
    add_redirect    => $redirects_feature,
    delete_redirect => $redirects_feature,
    redirect_info   => $allow_demo,
    list_hotlinks   => $hotlink_feature,
    add_hotlink     => $hotlink_feature,
    delete_hotlink  => $hotlink_feature,
);

use bytes;    #case 15186

use Cpanel::API ();

use Cpanel::Imports;

our $VERSION = '1.1';

##################################################
## cpdev: MIME
sub list_mime {
    my ( $args, $result ) = @_;
    my $type = $args->get('type');

    my %MIMETYPES;

    if ( $type eq 'system' ) {
        my ($SYSMIME) = _system_mime();
        foreach my $mimetype ( keys %$SYSMIME ) {
            $MIMETYPES{$mimetype} = {
                type      => $mimetype,
                extension => $SYSMIME->{$mimetype},
                origin    => 'system'
            };
        }
    }

    if ( $type eq 'user' ) {
        my ( $USERMIME, $msg ) = _user_mime();
        if ( not defined $USERMIME and defined $msg ) {
            $result->raw_error($msg);
            return;
        }

        foreach my $mimetype ( keys %$USERMIME ) {
            next unless _is_valid_mime_type($mimetype);
            $MIMETYPES{$mimetype} = {
                type      => $mimetype,
                extension => $USERMIME->{$mimetype},
                origin    => 'user'
            };
        }
    }

    my @TMIME = sort { $a->{'type'} cmp $b->{'type'} } values %MIMETYPES;
    $result->data( \@TMIME );
    return 1;
}

sub add_mime {
    my ( $args, $result )    = @_;
    my ( $type, $extension ) = $args->get( 'type', 'extension' );

    $type      =~ s/\s//g;
    $extension =~ s/(^\s|\s$)//g;

    $extension = Cpanel::Encoder::Tiny::safe_html_encode_str($extension);

    if ( !$type || !$extension ) {
        $result->error('You must fill in the extension as well as the type.');
        return;
    }
    if ( !_is_valid_mime_type($type) ) {
        $result->error('You must provide a valid MIME type.');
        return;
    }

    my $docrootslist_ref = Cpanel::DomainLookup::getdocrootlist();
    foreach my $docroot ( keys %{$docrootslist_ref} ) {
        my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($docroot);
        my $htaccess_sr    = $htaccess_trans->get_data();

        $$htaccess_sr =~ s<^\s*addtype\s+\Q$type\E\s+\Q$extension\E\s*$><>img;

        $$htaccess_sr .= "\n" if substr( $$htaccess_sr, -1 ) ne "\n";
        $$htaccess_sr .= "AddType $type $extension\n";

        $htaccess_trans->save_and_close_or_die();
    }

    return 1;
}

sub _is_valid_mime_type {
    my $mime = shift;
    my ( $type, $subtype ) = split( '/', $mime, 2 );

    foreach my $name ( $type, $subtype ) {
        return unless $name;
        return if length($name) > 127;
        return unless index( $name, "\n" ) == -1;
        return unless $name =~ /^[a-zA-Z0-9!#\$&\.\+\-\^\_]+$/;
    }
    return 1;
}

sub delete_mime {
    my ( $args, $result ) = @_;
    my $type = $args->get('type');

    my $docrootslist_ref = Cpanel::DomainLookup::getdocrootlist();
    foreach my $docroot ( keys %{$docrootslist_ref} ) {
        my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($docroot);
        my $htaccess_sr    = $htaccess_trans->get_data();

        ## CPANEL-10464: support for multiple extensions, or in regex speak,
        ## a (non-remembered) non-greedy one-or-more of spaces and non-spaces
        ## after the $type
        $$htaccess_sr =~ s<^\s*addtype\s+\Q$type\E(?:\s+\S+)+?\s*$><>img;
        $htaccess_trans->save_and_close_or_die();
    }

    return 1;
}

##################################################
## cpdev: HANDLERS
sub list_handlers {
    my ( $args, $result ) = @_;
    my $type = $args->get('type');

    my @THANDLERS;
    my %HANDLERSTYPES;

    if ( $type eq 'system' ) {
        my ($SYSHANDLERS) = _system_handlers();
        foreach my $handler ( keys %$SYSHANDLERS ) {
            $HANDLERSTYPES{$handler} = {
                extension => $handler,
                handler   => $SYSHANDLERS->{$handler},
                origin    => 'system'
            };
        }
    }

    if ( $type eq 'user' ) {
        my ( $USERHANDLERS, $msg ) = _user_handlers();
        if ( not defined $USERHANDLERS and defined $msg ) {
            $result->raw_error($msg);
            return;
        }

        foreach my $handler ( keys %$USERHANDLERS ) {
            $HANDLERSTYPES{$handler} = {
                handler   => $USERHANDLERS->{$handler},
                extension => $handler,
                origin    => 'user'
            };
        }
    }

    foreach my $mtype ( keys %HANDLERSTYPES ) {
        push @THANDLERS, $HANDLERSTYPES{$mtype};
    }

    @THANDLERS = sort { $a->{'handler'} cmp $b->{'handler'} } @THANDLERS;

    $result->data( \@THANDLERS );
    return 1;
}

sub add_handler {
    my ( $args,      $result )  = @_;
    my ( $extension, $handler ) = $args->get( 'extension', 'handler' );

    $handler   =~ s/\s//g;
    $extension =~ s/(^\s|\s$)//g;

    $handler   = Cpanel::Encoder::Tiny::safe_html_encode_str($handler);
    $extension = Cpanel::Encoder::Tiny::safe_html_encode_str($extension);

    if ( $handler eq "" || $extension eq "" ) {
        $result->error('You must fill in the extension as well as the handler.');
        return;
    }

    my $docrootslist_ref = Cpanel::DomainLookup::getdocrootlist();
    foreach my $docroot ( keys %{$docrootslist_ref} ) {
        my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($docroot);
        my $htaccess_sr    = $htaccess_trans->get_data();

        $$htaccess_sr =~ s<^\s*addhandler\s+\Q$handler\E\s+\Q$extension\E\s*$><>img;

        $$htaccess_sr .= "\n" if substr( $$htaccess_sr, -1 ) ne "\n";
        $$htaccess_sr .= "AddHandler $handler $extension\n";

        $htaccess_trans->save_and_close_or_die();
    }

    return 1;
}

sub delete_handler {
    my ( $args, $result ) = @_;
    my $extension = $args->get('extension');

    $extension =~ s/^\s//g;

    my $docrootslist_ref = Cpanel::DomainLookup::getdocrootlist();
    foreach my $docroot ( keys %{$docrootslist_ref} ) {
        my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($docroot);
        my $htaccess_sr    = $htaccess_trans->get_data();

        $$htaccess_sr =~ s<^\s*addhandler\s+\S+\s+\Q$extension\E\s*$><>img;

        $htaccess_trans->save_and_close_or_die();
    }

    return 1;
}

##################################################
## cpdev: REDIRECTS
sub list_redirects {
    my ( $args, $result ) = @_;

    my ( $regex, $filter_destination ) = $args->get(qw{ regex destination });

    my @REDIRECTS = Cpanel::HttpUtils::Htaccess::getredirects();
    my @OKREDIRECTS;
    foreach my $redirect (@REDIRECTS) {
        ## adapting the keys without deleting the previous pollutes the object; see is_deeply
        ##   in the test suite
        $redirect->{'source'} = $redirect->{'sourceurl'};
        if ( $redirect->{'source'} eq '(.*)' || $redirect->{'source'} eq '.*' ) {
            $redirect->{'displaysourceurl'} = 'ALL';
        }
        else {
            $redirect->{'displaysourceurl'} = $redirect->{'sourceurl'};
        }

        $redirect->{'destination'} = $redirect->{'targeturl'};

        if ($filter_destination) {
            my $destination = $redirect->{'destination'} // '';
            $destination        =~ s{/+$}{};
            $filter_destination =~ s{/+$}{};
            next if $destination ne $filter_destination;
        }

        if ( $redirect->{'domain'} eq '.*' ) {
            $redirect->{'urldomain'}     = $Cpanel::CPDATA{'DNS'};
            $redirect->{'displaydomain'} = 'ALL';
        }
        else {
            $redirect->{'urldomain'}     = $redirect->{'domain'};
            $redirect->{'displaydomain'} = $redirect->{'domain'};
        }

        $redirect->{'matchwww_text'} = $redirect->{'matchwww'} ? 'checked' : '';
        $redirect->{'wildcard_text'} = $redirect->{'wildcard'} ? 'checked' : '';

        if (   defined $regex
            && $regex ne ''
            && $redirect->{'sourceurl'} !~ /\Q$regex\E/i ) {
            next;
        }

        push @OKREDIRECTS, $redirect;
    }

    @OKREDIRECTS =
      sort { $a->{'displaydomain'} cmp $b->{'displaydomain'} } @OKREDIRECTS;

    $result->data( \@OKREDIRECTS );
    return 1;
}

=head2 add_redirect( => ..., domain => ..., ,  => ..., src => ..., ,  => ..., redirect => ..., ,  => ..., type => ..., ,  => ..., redirect_wildcard => ..., ,  => ..., redirect_www => ..., )

=head3 ARGUMENTS

=over

=item domain - string [REQUIRED]

The domain to attach the redirect.

=item src - string

The relative file path to the C<domain> that you wish to redirect to another location.

=item redirect - string [REQUIRED]

The full URL, with protocol, to the new location.

=item type - enum

This value defaults to C<permanent>. You must include one of the following strings:

=over

=item permanent

The web server responds with a HTTP 301 permanent redirect.

=item temp

The web server responds with a HTTP 307 temporary redirect.

=back

=item redirect_wildcard - boolean

Whether to redirect all files within a directory to the same filename within the destination directory.

This value defaults to 0.

=over

=item 1 - Redirect all files within the directory.

=item 0 - Do not redirect all files within

=back

=item redirect_www - number

Whether to redirect domains with or without www.

This value defaults to 0.

=over

=item 2 - Redirect with www.

=item 1 - Redirect without www.

=item 0 - Redirect with and without www.

=back

=back

=head3 RETURNS

n/a

=head3 THROWS

=over

=item When the C<src> parameter contains a protocol such as http://, https://, ...

=item When the C<redirect> URL is longer than 255 characters.

=item When the C<redirect> URL is not provided.

=item When the requested configuration causes a redirect loop.

=item There may be other less common issues as well.

=back

=head3 EXAMPLES

=head4 Command line usage to disable a redirect

    uapi --user=cpuser --output=jsonpretty Mime add_redirect domain=example.com src=index.html redirect=https://example.new.com/index.html type=permanent

=head4 Template Toolkit

    [% SET result = execute('Mime', 'add_redirect', {
            domain   => 'example.com',
            src      => 'index.html',
            redirect => 'https://example.new.com/index.html',
            type     => 'permanent',
       }); %]
    [% IF result.status %]
        Redirect added.
    [% ELSE %]
        Failure message
    [% END %]

=cut

sub add_redirect {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $args, $result ) = @_;

    my ( $domain, $redirect ) = $args->get_required(qw/domain redirect/);
    my ( $src, $type, $redirect_wildcard, $redirect_www ) = $args->get(qw/src type redirect_wildcard redirect_www/);

    if ( not defined $src ) {
        $src = "/";
    }

    # do not allow *any* protocol like http://, https://, ftp://, ... at the beginning of $src.
    if ( $src =~ m{^\S+[:][/][/]} ) {
        die Cpanel::Exception::create(
            'InvalidParameter',
            'The “[asis,src]” parameter must be a path and may not contain “://”.'
        );
    }

    $type = 'permanent' if !$type || $type ne 'permanent' && $type ne 'temp';

    # make sure we have a protocol in $redirect
    if ( $redirect !~ m{^\S+[:][/][/].+} ) {
        $redirect = "http://$redirect";
    }

    # Encode before passing off to url_decode_str to avoid plus signs being transliterated into spaces.
    $redirect =~ s{\+}{%2b};

    # Apache does not allow these in the rules
    $redirect = Cpanel::Encoder::URI::uri_decode_str($redirect);
    $redirect =~ s/ /%20/g;
    $redirect =~ s{\s}{}g;    # [\n\r\t\f] but the %20 trick before anf after lets use do \s
    $redirect =~ s/%20/ /g;

    if ( length $redirect > 255 ) {
        $result->error('URL is too long.');
        return;
    }
    if ( length $redirect == 7 ) {

        # its just the protocol we prepended: empty it so it can fallback to error below
        $redirect = '';
    }

    $src =~ s/\?[^\?]*//g;
    $src =~ s/[\t\n\r\f]+//g;
    $src = quotemeta($src);

    if ( !$type || !$redirect || $redirect =~ /^\// ) {
        $result->error('You must fill in the full url to redirect to.');
        return;
    }

    if ( $src =~ /\*$/ ) {
        $src =~ s/\*$//g;
        $redirect_wildcard = 1;
    }

    if ( $redirect =~ /\*$/ ) {
        $redirect =~ s/\*$//g;
        $redirect_wildcard = 1;
    }

    $src =~ s/^\/+//g;    #strip leading slashes
    $src =~ tr{/}{}s;     # collapse //s to /

    my $source_url = 'http://' . $domain . '/' . $src;
    my ( $src_islocal, $src_localpath, $src_protocol ) = Cpanel::DomainLookup::resolve_url_to_localpath($source_url);

    if ( $domain eq '.*' || $domain eq '(.*)' ) {
        $src_islocal   = 1;
        $src_localpath = $Cpanel::homedir . '/' . $src;
    }

    my ( $dest_islocal, $dest_localpath, $dest_protocol ) = Cpanel::DomainLookup::resolve_url_to_localpath($redirect);

    my $testurl      = $redirect;
    my $testsrc      = $src;
    my ($testdomain) = $redirect =~ m{//(.*?)(?:/|$)}g;
    $testurl =~ s/\/+$//g;
    $testsrc =~ s/\/+$//g;
    $testdomain //= '';

    my $same_domain = $testdomain eq $domain
      || ( $testdomain eq "www.$domain"
        && defined $redirect_www
        && $redirect_www != 1 );

    my $exclude_dest_protocol = 0;
    if ($redirect_wildcard) {
        if (   $same_domain
            && $src_islocal
            && $dest_islocal
            && substr( $dest_localpath, 0, length $src_localpath ) eq $src_localpath ) {
            if ( $src_protocol eq $dest_protocol ) {

                $result->error(
                    'Redirecting "[_1]" to "[_2]" will cause a redirection loop because "http://[_3]/[_1]", which is located at "[_4]", is above "[_2]", which is located at "[_4]" .',
                    $src, $redirect, $domain, $src_localpath
                );
                return;
            }
            else {
                $exclude_dest_protocol = 1;
            }
        }
    }
    else {

        if (
            'http://' . $domain . '/' . $testsrc eq $testurl
            || (   $same_domain
                && $src_islocal
                && $dest_islocal
                && $src_localpath eq $dest_localpath )
        ) {
            if ( $src_protocol eq $dest_protocol ) {
                $result->error(
                    'You cannot redirect "[_1]" to "[_2]" as this will cause a redirection loop because "[_3]" is at the same place as "[_4]".',
                    $testsrc, $testurl, $src_localpath, $dest_localpath
                );
                return;
            }
            else {
                $exclude_dest_protocol = 1;
            }
        }
        if (   ( $domain eq '.*' || $domain eq '(.*)' )
            && ( $src_islocal && $dest_islocal && $testurl =~ /http\:\/\/[^\/]+$/ ) ) {
            if ( $src_protocol eq $dest_protocol ) {
                $result->error(
                    'You cannot redirect "[_1]" to "[_2]" as this will cause a redirection loop because "[_3]" is the document root of one of your domains.',
                    $testsrc, $testurl, $dest_localpath
                );
            }
            else {
                $exclude_dest_protocol = 1;
            }
            return;
        }
    }

    $domain = '.*' if ( !defined $domain || $domain eq '' );

    my $docroot = Cpanel::DomainLookup::getdocroot($domain);

    Cpanel::API::execute(
        "Mime",
        "delete_redirect",
        {
            domain  => $domain,
            src     => $src,
            docroot => $docroot
        }
    );

    #even though apache handles this ok
    #we want the most current one
    my $matchurl = $src;
    if ($redirect_wildcard) {
        $matchurl .= ( $src =~ /\/$/ ? '?' : '/?' );
    }
    elsif ($src_islocal) {
        if ( -d $src_localpath ) {
            $matchurl .= ( $src =~ /\/$/ ? '?' : '/?' );
        }
    }
    elsif ( $src !~ /\.(html|htm|jsp|cgi|pl|php|asp|ppl|plx|perl|shtml|js|php[1-9][0-9]*|phtml|pht|phtm)$/ ) {
        $matchurl .= ( $src =~ /\/$/ ? '?' : '/?' );
    }
    $matchurl .= ( $redirect_wildcard ? '(.*)$' : '$' );

    # this way full domain wildcards will work via /$1 and this will not break
    # DOM/.../$1 DOM/...?$1 or DOM/...$1 style ones
    if ( $redirect =~ m{^\S+[:][/][/][^/]+$} ) {
        $redirect .= '/';
    }

    my ( $status, $msg ) = Cpanel::HttpUtils::Htaccess::setupredirection(
        'docroot'               => $docroot,
        'domain'                => $domain,
        'redirecturl'           => $redirect,
        'code'                  => ( $type =~ /temp/i ? 302 : 301 ),
        'matchurl'              => $matchurl,
        'rdwww'                 => $redirect_www,
        'exclude_dest_protocol' => $exclude_dest_protocol,
    );

    if ( $domain eq '.*' && $status ) {
        my $docroots = Cpanel::DomainLookup::getdocrootlist();

        foreach my $root ( keys %$docroots ) {
            ( $status, $msg ) = Cpanel::HttpUtils::Htaccess::setup_rewrite($root);
            last unless $status;
        }
    }

    #^ gets added to the front of $src automatically

    if ( !$status ) {
        $result->raw_error($msg);
        return;
    }

    $result->raw_message($msg);
    return 1;
}

## note: called internally by &add_redirect
sub delete_redirect {
    my ( $args, $result ) = @_;

    #What is the point of “docroot” if we already give the domain?
    my ( $domain, $src, $docroot ) = $args->get( 'domain', 'src', 'docroot' );
    my $args_str = $args->get('args') || undef;

    if ( !$docroot ) {
        $docroot = Cpanel::DomainLookup::getdocroot($domain);
    }
    else {
        $docroot = Cpanel::SafeDir::Fixup::homedirfixup($docroot);
    }

    my ( $status, $msg );

    # Must have the full argument string if deleteing a Redirect or RedirectMatch
    if ($args_str) {

        my @HC;
        my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($docroot);
        $args_str =~ s/^\s+|\s+$//g;
        $args_str = Cpanel::StringFunc::Case::ToLower($args_str);    # use ToLower to avoid unicode import
        foreach my $line ( split( m{\n}, ${ $htaccess_trans->get_data() } ) ) {
            ( my $trimmed_line = $line ) =~ s/^\s+|\s+$//;
            if ( $trimmed_line !~ /^Redirect(?:Match)?\s+\Q$args_str\E$/i ) {
                push @HC, $line . "\n";
            }
        }
        $htaccess_trans->set_data( \join( '', @HC ) );

        my ( $status, $msg ) = Cpanel::HttpUtils::Htaccess::test_and_install_htaccess(
            'installdir'     => $docroot,
            'htaccess_trans' => $htaccess_trans,
        );
        if ( !$status ) {
            $result->raw_error($msg);
            return;
        }
    }
    else {
        $src = '' if !defined $src;
        $src =~ s/^\s+//g;
        $src = '' if $src eq '\/';    # this will make '' and '/' be synonymous

        my ( $status, $msg ) = Cpanel::HttpUtils::Htaccess::disableredirection(
            $docroot,
            ( length($domain) ? $domain : '.*' ), $src
        );

        if ( !$status ) {
            $result->raw_error($msg);
            return;
        }
    }

    $result->raw_message($msg);
    return 1;
}

## combination api2_redirecturlname and api2_redirectname; really,
##   this logic should just be in the template
sub redirect_info {
    my ( $args, $result ) = @_;
    my ( $url,  $domain ) = $args->get(qw(url domain));

    my %data = ();
    if ( $url eq '.*' || $url eq '(.*)' ) {
        $url = '** All Requests **';
    }
    if ( $domain eq '.*' ) {
        $domain = '** All Public Domains **';
    }
    $data{url}    = $url;
    $data{domain} = $domain;
    $result->data( \%data );
    return 1;
}

=head2 get_redirect(domain => ...)

=head3 ARGUMENTS

=over

=item domain - string

The domain for which to look up the redirect URL.

=back

=head3 RETURNS

=over

=item redirection_enabled - boolean

True if a redirect URL is set. False otherwise.

=item url - string

The redirect URL. When redirection is not enabled, this will come back as null.

=back

=head3 THROWS

=over

=item When a required argument is not provided.

=item When the directory for the specified domain cannot be found.

=item When the .htaccess file cannot be opened.

=back

=head3 EXAMPLES

=head4 Command line usage to disable a redirect

    uapi --user=cpuser --output=jsonpretty Mime get_redirect domain=example.com

The function returns only metadata.

=head4 Template Toolkit

    [% SET result = execute('Mime', 'get_redirect', { 'domain' => RAW_FORM.domain }); %]
    [% IF result.status %]
        Redirect URL: [% result.data.url %]
    [% ELSE %]
        Failure message
    [% END %]

=cut

sub get_redirect {
    my ( $args, $result ) = @_;
    my $domain = $args->get_length_required('domain');

    _validate_domain_ownership($domain);

    my $docroot = Cpanel::DomainLookup::getdocroot($domain);
    _validate_docroot( $domain, $docroot );

    require Cpanel::HttpUtils::Htaccess;

    my ( $status, $url, $redirection_enabled ) = Cpanel::HttpUtils::Htaccess::getrewriteinfo( $docroot, $domain );

    if ($url) {
        $url =~ s/\%\{REQUEST_URI\}/\//g;
        $url =~ s/\$1//g;
    }
    else {
        $url = undef;
    }

    $result->data(
        {
            redirection_enabled => $redirection_enabled,
            url                 => $url,
        },
    );
    return 1;
}

# _validate_docroot(DOMAIN, DOCROOT)
#
# Given a domain dies if the docroot is not defined for that domain.
sub _validate_docroot {
    my ( $domain, $docroot ) = @_;
    if ( !$docroot ) {
        die locale()->maketext(
            'The system failed to locate a document root for the domain “[_1]”.',
            $domain
        ) . "\n";
    }
    return 1;
}

# _validate_domain_ownership(DOMAIN)
#
# Given a domain dies if the domain is not owned by the current cPanel user.
sub _validate_domain_ownership {
    my ($domain) = @_;
    if (
        Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner(
            $domain,
            { default => '' }
        ) ne $Cpanel::user
    ) {
        die locale()->maketext( 'The “[_1]” domain is not owned by this account.', $domain ) . "\n";
    }

}

##################################################
## cpdev: HOTLINKS
sub list_hotlinks {
    ## no args
    my ( $args, $result ) = @_;

    my $htaccess = "$Cpanel::homedir/public_html/.htaccess";
    if ( !-e $htaccess ) {
        Cpanel::FileUtils::TouchFile::touchfile($htaccess);
    }

    ## defaults
    my %data = (
        state        => 'disabled',
        urls         => undef,        ## collected from %URLS
        allow_null   => 0,
        extensions   => undef,
        redirect_url => undef,        ## $redirect_url,
    );

    ## $nextrule acts as a state variable
    my ( %URLS, $nextrule );

    if ( open my $htaccess_fh, "<", $htaccess ) {
        while ( my $line = readline $htaccess_fh ) {
            if ( $line =~ /^\s*RewriteCond\s+\%\{HTTP_REFERER\}\s+(.*)/i ) {
                my $rest = $1;
                $nextrule = 1;
                ## from &hotlinkingenabled
                $data{'state'} = 'enabled';
                ## from &linkallownull
                if ( $rest eq '!^$' ) {
                    $data{'allow_null'} = 1;
                }
                else {
                    ## from &gethotlinkurls
                    $rest =~ s/^\!\^//g;         ## remove literal !^ from beginning
                    $rest =~ /(\S+)/;            ## trim whitespace from end
                    $rest = $1;
                    $rest =~ s!/\.\*\$$!!g;      ## remove literal /.*$ at end
                    next if ( $rest eq '$' );    ## probably not possible, but does not hurt
                    $rest =~ s/\$*$//g;
                    if ( $rest ne "" ) {
                        $URLS{$rest} = 1;
                    }
                }
            }
            ## next clause is combination &gethotlinkext and &gethotlinkrurl
            elsif ( $nextrule && $line =~ /^\s*RewriteRule/i ) {
                $nextrule = 0;
                my ( undef, $_extension, $_url ) = split( /\s+/, $line );
                $_extension =~ /\(([^\)]+)\)/;    ## grab all the extensions within the parens
                $data{'extensions'} = $1;
                $data{'extensions'} =~ s/\|/\,/g;
                $data{'extensions'} =~ s/\s//g;
                $data{'extensions'} =~ s/\n//g;

                if ( $_url ne "-" ) {
                    $data{'redirect_url'} = $_url;
                }
            }
        }
        close $htaccess_fh;
    }
    else {
        $result->error( 'Error: while opening [_1]', $htaccess );
    }

    unless ( scalar keys %URLS ) {
        _collect_default_hotlink_urls( \%URLS );
    }

    if ( ( not defined $data{'extensions'} ) || ( $data{'extensions'} eq "" ) ) {
        $data{'extensions'} = "jpg,jpeg,gif,png,bmp";
    }

    $data{'urls'} = [ sort keys %URLS ];

    $result->data( \%data );
    return 1;
}

sub _collect_default_hotlink_urls {
    my ($urls_ref) = @_;
    my $userdata = Cpanel::Config::userdata::Load::load_userdata_main($Cpanel::user);
    foreach my $domain (
        $Cpanel::CPDATA{'DNS'},             @{ $userdata->{'sub_domains'} },
        @{ $userdata->{'parked_domains'} }, keys %{ $userdata->{'addon_domains'} }
    ) {
        foreach my $prefix ( 'www.', '' ) {
            foreach my $scheme (qw/http https/) {
                $urls_ref->{"$scheme://$prefix$domain"} = 1;
            }
        }
    }
    return;
}

sub add_hotlink {
    my ( $args, $result ) = @_;
    my ( $urls, $extensions, $allow_null, $redirect_url ) = $args->get( 'urls', 'extensions', 'allow_null', 'redirect_url' );

    ## remove all entries
    Cpanel::API::execute( "Mime", "delete_hotlink" );

    my @URLS = split /\n/, $urls;
    $extensions =~ s/^\s*|\s*$//g;
    $extensions =~ s/^\,*|\,*$//g;
    $extensions =~ s/[\s\,]/\|/g;

    my $docrootslist_ref = Cpanel::DomainLookup::getdocrootlist();
    foreach my $docroot ( keys %{$docrootslist_ref} ) {
        my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($docroot);
        my @HTACCESS       = split( m<^>m, ${ $htaccess_trans->get_data() } );
        push @HTACCESS, "\n";
        if ( !grep ( /^\s*RewriteEngine\s*\"?on/i, @HTACCESS ) ) {
            unshift @HTACCESS, 'RewriteEngine on' . "\n";
        }

        if ($allow_null) {
            push @HTACCESS, 'RewriteCond %{HTTP_REFERER} !^$' . "\n";
        }
        foreach my $url (@URLS) {
            $url =~ s/[\n\r]//g;
            if ( $url =~ m/:\/\// ) {
                $url =~ s/\/$//g;
                push @HTACCESS,
                  'RewriteCond %{HTTP_REFERER} !^' . $url . '/.*$      [NC]' . "\n";
                push @HTACCESS,
                  'RewriteCond %{HTTP_REFERER} !^' . $url . '$      [NC]' . "\n";
            }
        }
        push @HTACCESS,
          'RewriteRule .*\.('
          . $extensions . ')$ '
          . (
            !$redirect_url
            ? '- [F,NC]'
            : $redirect_url . ' [R,NC]'
          ) . "\n\n";

        $htaccess_trans->set_data( \join( '', @HTACCESS ) );

        my ( $status, $msg ) = Cpanel::HttpUtils::Htaccess::test_and_install_htaccess(
            'installdir'     => "$Cpanel::homedir/public_html",
            'htaccess_trans' => $htaccess_trans,
        );

        if ( !$status ) {
            $result->raw_error($msg);
            return;
        }
    }
    return 1;
}

sub delete_hotlink {
    ## no args
    my ( $args, $result ) = @_;

    my $docrootslist_ref = Cpanel::DomainLookup::getdocrootlist();
    foreach my $docroot ( keys %{$docrootslist_ref} ) {
        my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($docroot);
        my @MOD_HTACCESS;
        my $skipnext = 0;
        foreach my $line ( split( m{\n}, ${ $htaccess_trans->get_data() } ) ) {
            if ( $line =~ /^\s*RewriteCond/i && $line =~ /\%\{HTTP_REFERER\}/ ) {
                $skipnext = 1;
                next;
            }
            elsif ( $skipnext && $line =~ /^\s*RewriteRule/i ) {
                $skipnext = 0;
                next;
            }
            push @MOD_HTACCESS, $line . "\n";
        }

        ## case 9770: remove RewriteEngine unless there exist *any* RewriteCond or RewriteRule
        ##   note the similar clause in ::Htaccess' disableredirection (that did not have the 9770 bug)
        if ( !grep ( /^\s*Rewrite(Cond|Rule)/i, @MOD_HTACCESS ) ) {
            @MOD_HTACCESS = grep ( !/^\s*RewriteEngine\s*\"?on/i, @MOD_HTACCESS );
        }
        $htaccess_trans->set_data( \join( '', @MOD_HTACCESS ) );

        my ( $status, $msg ) = Cpanel::HttpUtils::Htaccess::test_and_install_htaccess(
            'installdir'     => "$Cpanel::homedir/public_html",
            'htaccess_trans' => $htaccess_trans,
        );

        if ( !$status ) {
            $result->raw_error($msg);
            return;
        }
    }

    return 1;
}

##################################################
## UTILITY FUNCTIONS (NON-API FUNCTIONS)
## functions moved from Cpanel::Mime in order to reduce the binary size of uapi.pl

sub _fetch_file_mtime {
    my $file = shift || return 0;

    return ( stat $file )[9] || 0;
}

our %system_types = (
    '.shtml'                   => 'server-parsed',
    '.cgi .pl .plx .ppl .perl' => 'cgi-script'
);

our %system_mimes = (
    'text/vnd.wap.wml'               => '.wml',
    'application/x-tar'              => '.tgz',
    'application/x-pkcs7-crl'        => '.crl',
    'text/html'                      => '.shtml',
    'image/vnd.wap.wbmp'             => '.wbmp',
    'application/x-x509-ca-cert'     => '.crt',
    'application/vnd.wap.wmlc'       => '.wmlc',
    'application/vnd.wap.wmlscriptc' => '.wmlsc',
    'application/x-gzip'             => '.gz .tgz',
    'text/vnd.wap.wmlscript'         => '.wmls',
    'application/x-compress'         => '.Z'
);

# MUST ALWAYS ALLOW LISTING OR FILEMANAGER WILL BREAK
sub _system_mime {
    my $now        = time;
    my $srmconf    = apache_paths_facade->file_conf_srm_conf();
    my $mimetypes  = apache_paths_facade->file_conf_mime_types();
    my $httpconf   = apache_paths_facade->file_conf();
    my $srm_mtime  = _fetch_file_mtime($srmconf);
    my $mime_mtime = _fetch_file_mtime($mimetypes);
    my $http_mtime = _fetch_file_mtime($httpconf);

    my %MIME;
    my $datastore_file  = Cpanel::CachedCommand::Utils::_get_datastore_filename('SYSTEMMIME');
    my $datastore_mtime = _fetch_file_mtime($datastore_file);
    if (
           $datastore_mtime > 0
        && $datastore_mtime < $now
        && ( $now - $datastore_mtime ) < 86_400    # case 63193 ( auto recover after 24 hours )
        && $datastore_mtime >= $srm_mtime
        && $datastore_mtime >= $mime_mtime
        && $datastore_mtime >= $http_mtime
    ) {
        eval {
            local $SIG{'__DIE__'}  = 'DEFAULT';
            local $SIG{'__WARN__'} = 'DEFAULT';
            %MIME = %{ Cpanel::AdminBin::Serializer::LoadFile($datastore_file) };
        };
    }

    if ( ( scalar keys %MIME ) < 5 ) {
        %MIME = %system_mimes;
        if ( open my $mime_fh, '<', $mimetypes ) {
            while ( my $line = readline $mime_fh ) {
                next if $line =~ m/^\s*#/;
                chomp $line;
                if ( $line =~ m/^(\S+)\s*(.*)/ ) {
                    my $mime      = $1;
                    my $extension = $2;
                    $extension =~ s/\s+$//;
                    next if !$extension;
                    my @extensions = split( /\s+/, $extension );
                    if ( $MIME{$mime} ) {
                        my @earlier_extension = split( /\s+/, $MIME{$mime} );
                        unshift @extensions, @earlier_extension;
                    }
                    $MIME{$mime} = join ' ', @extensions;
                }
            }
            close $mime_fh;
        }

        if ( open my $mime_fh, '<', $srmconf ) {
            while ( my $line = readline $mime_fh ) {
                next if $line =~ m/^\s*#/;
                chomp $line;
                if ( $line =~ m/^\s*addtype\s+(\S+)\s*(.*)/ ) {
                    my $mime      = $1;
                    my $extension = $2;
                    $extension =~ s/\s+$//;
                    next if !$extension;
                    my @extensions = split( /\s+/, $extension );
                    if ( $MIME{$mime} ) {
                        my @earlier_extension = split( /\s+/, $MIME{$mime} );
                        unshift @extensions, @earlier_extension;
                    }
                    $MIME{$mime} = join ' ', @extensions;
                }
            }
            close $mime_fh;
        }

        foreach my $value ( values %MIME ) {
            $value = join ' ',
              Cpanel::ArrayFunc::Uniq::uniq( sort split /\s+/, $value );
        }

        unless ( Cpanel::FileUtils::Write::overwrite_no_exceptions( $datastore_file, Cpanel::AdminBin::Serializer::Dump( \%MIME ), 0600 ) ) {
            logger->warn("Could not write system mime cache to $datastore_file: $!");
            unlink $datastore_file;    # avoid corruption
        }
    }

    return ( \%MIME );
}

# MUST ALWAYS ALLOW LISTING OR FILEMANAGER WILL BREAK
sub _user_mime {
    my $htaccess = "$Cpanel::homedir/public_html/.htaccess";

    return unless -r $htaccess;

    if ( open my $ht_fh, '<', $htaccess ) {
        my %MIME;
        while ( my $line = readline $ht_fh ) {
            if ( $line =~ m/^\s*addtype\s+(\S+)\s+(.*)/i ) {
                my $mime      = $1;
                my $extension = $2;
                $extension =~ s/\s+$//;
                next if !$extension;
                my @extensions = split /\s+/, $extension;
                if ( $MIME{$mime} ) {
                    my @earlier_extension = split /\s+/, $MIME{$mime};
                    unshift @extensions, @earlier_extension;
                }
                $MIME{$mime} = join ' ', Cpanel::ArrayFunc::Uniq::uniq(@extensions);
            }
        }
        close $ht_fh;
        return ( \%MIME );
    }
    else {
        logger->warn("Failed to read $htaccess: $!");
        return ( undef, locale->maketext( 'Error while opening “[_1]”.', $htaccess ) );
    }
}

# MUST ALWAYS ALLOW LISTING OR FILEMANAGER WILL BREAK
sub _system_handlers {
    my %HANDLERS = %system_types;

    my $srmconf = apache_paths_facade->file_conf_srm_conf();
    if ( -r $srmconf ) {
        if ( open my $srm_fh, '<', $srmconf ) {
            while ( my $line = readline $srm_fh ) {
                if ( $line !~ m/^\#/ && $line =~ m/^addhandler\s+(\S+)\s*(.*)$/i ) {
                    next if ( $1 eq '' || $2 eq '' );
                    $HANDLERS{$2} = $1;
                }
            }
            close $srm_fh;
        }
        else {
            logger->warn("Failed to read $srmconf: $!");
        }
    }

    return ( \%HANDLERS );
}

# MUST ALWAYS ALLOW LISTING OR FILEMANAGER WILL BREAK
sub _user_handlers {
    my $htaccess = "$Cpanel::homedir/public_html/.htaccess";

    if ( !-e $htaccess ) {
        Cpanel::FileUtils::TouchFile::touchfile($htaccess);
        return;
    }

    if ( open my $htaccess_fh, '<', $htaccess ) {
        my %HANDLERS;
        while ( my $line = readline $htaccess_fh ) {
            if ( $line =~ m/^\s*addhandler\s+(\S+)\s+(\S.*?)\s*$/i ) {
                $HANDLERS{$2} = $1;
            }
        }
        close $htaccess_fh;
        return ( \%HANDLERS );
    }
    else {
        logger->warn("Failed to read $htaccess: $!");
        return ( undef, locale->maketext( 'Error while opening “[_1]”.', $htaccess ) );
    }
}

1;
