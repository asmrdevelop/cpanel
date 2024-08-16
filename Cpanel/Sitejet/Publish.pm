package Cpanel::Sitejet::Publish;

# cpanel - Cpanel/Sitejet/Publish.pm               Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::AccessIds;
use Cpanel::API::NginxCaching ();
use Cpanel::Autodie;
use Cpanel::Autodie::Unlink;
use Cpanel::Exception;
use Cpanel::Logger;
use Cpanel::SafeRun::Errors;
use Cpanel::Tar;
use Cpanel::WebDisk();
use Cpanel::AccessIds::ReducedPrivileges();
use Cpanel::Chdir();
use Cpanel::DomainLookup          ();
use Cpanel::DomainLookup::DocRoot ();
use Cpanel::Sitejet::Connector    ();
use Cpanel::SSL::Domain           ();
use Cpanel::WebVhosts             ();
use Cpanel::XMLParser             ();
use File::Basename                ();
use File::MimeInfo                ();
use File::Path                    ();
use LWP::UserAgent;
use URI::Split    qw(uri_split);
use URI::XSEscape ();

use constant retry_limit => 5;

my @CDN_HOSTS = (
    'https://inter-cdn.com',
    'https://cdn1.site-media.eu',
    'https://cdn2.site-media.eu',
    'https://cdn3.site-media.eu',
    'https://cdn4.site-media.eu',
    'https://cdn5.site-media.eu',
    'https://cdn6.site-media.eu',
    'https://cdn7.site-media.eu'
);

my $PATH_SITEMAP = '/sitemap.xml';

# Regex to parse all URLs referring to assets
my $REGEX_ASSETS = qr{/(?:images|webcard|g|js|css)/[^"') ]+};

# Regex to parse JS chunks in bundled JS file
my $REGEX_JS_CHUNKS = qr{\((\d+)\)\.then};

# Regex to detect whether a filename has an extension
my $REGEX_FILE_EXT = qr!(.*)\.[a-zA-Z0-9]{2,5}$!;
my $language_set   = 0;

# Regex to parse XML
my $REGEX_RSS = qr{<link\b(?=[^>]*type="application\/rss\+xml")(?=[^>]*rel="alternate")(?:[^>]+)?href="([^"\'>]+)"(?:[^>]+)?\/?>};

our $start;
our $origin;
our $domain;
our $ssl_status;

my $retry_attempts = 0;

our $logger;
our $document_root;

my %processed_urls;

=encoding utf-8

=head1 NAME

Cpanel::Sitejet::Publish

=head1 DESCRIPTION

Module to publish (clone) a complete website from Sitejet's site to a cPanel
user's server.  Any files residing external to Sitejet's site such as a CDN
server will be copied to the cPanel server so that everything for that website
is local to the cPanel server.

This module matches Plesk's SitejetPublish.php in the sitejet-plesk repo. The
names of subroutines and variables in Perl match as much as possible, so that
future changes can be easily replicated.

The Plesk PHP naming convention for subroutines and variables is camelCase, so
their counterparts in this cPanel module match.

The cPanel standard naming convention is snake_case, except for module names
which are camelCase. Any subroutine or variable that is named using snake_case
does NOT have a corresponding PHP equivalent in the Plesk source code.

Subroutines whose names begin with "cp_" have no corresponding subroutine in
the original Plesk PHP source code. "cp_" just indicates the subroutine
originated with cPanel.

Publishing a website puts that website in the document root directory for the
appropriate domain or sub-domain.  If it is the first time a Sitejet publish is
done for that document root and if any files or directories already exist in
that document root directory then a compressed backup copy of those files and
directories is made in the cPanel user's home directory before they are
removed.  Subsequent Sitejet publish actions will overwrite everything that is
in that document root directory.

=cut

Cpanel::Sitejet::Publish::publish(shift) unless caller;

=head1 METHODS

=over

=item * publish -- Publishes Sitejet server-based website on cPanel server.

    ARGUMENTS
        websiteId (string) -- Unique website ID
        logfile (string) -- Full pathname of log file which is linked for UI streaming

    RETURNS
        1 if no errors.

    ERRORS
        All failures are fatal.
        Fails if cannot contact Sitejet server.

    Note:  Will not fail if some files cannot be downloaded, but resulting
    cloned site will appear to be incomplete.  Log will contain list of files
    that failed to download.

    EXAMPLE
        my $result = Cpanel::Sitejet::Publish::publish( $websiteId, $logfile );

=back

=cut

sub publish {
    my $logfile;
    ( $domain, $logfile ) = @_;
    $logger = Cpanel::Logger->new( { 'alternate_logfile' => $logfile } );
    $start  = time;

    my %opts = ( service => 'cpanel' );
    $ssl_status = ( Cpanel::SSL::Domain::get_best_ssldomain_for_object( $domain, \%opts ) )[1]->{is_currently_valid};

    # Must write something to logger immediately so the streamer can find it
    log_message("Starting sync for $domain at $start.");

    log_message("SSL enabled: $ssl_status");

    my $connector = Cpanel::Sitejet::Connector->new();
    $document_root = get_document_root($domain);
    my ( $urls, $etag ) = cp_process_sitemap( $connector, $domain );

    my @finishedUrls  = ();
    my $trackProgress = 1;

    # backs up all, and removes select public_html files
    my $user_metadata = $connector->cp_load_sitejet_metadata($domain);

    # TODO: DUCK-9753 Remove unused code
    # we are not doing back-up's any more.
    #cleanup() if !$user_metadata->{publish_status};

    my @iterations = ();
    my @retryUrls  = ();
    my $iteration  = 0;

    # get the latest sitemap urls before we parse assets
    my %processed_sitemap;

    # install API proxy
    $connector->installApiProxy( $domain, $document_root );

    # unzip the flags.tar.gz
    $connector->installFlags($document_root);

    my $percent = 10;
    log_message("Completed status: $percent%");

    my ( $total_parse_asset_url, $completed, $previous_status ) = ( 0, 0, 0 );

    # we have already completed 10% progress
    my $percent_increment = 90 / @$urls;

    # Execute all requests
    foreach my $url (@$urls) {
        _fetch_one_file_with_retry( $url, $etag, retry_limit(), $connector );
        $percent += $percent_increment;
        log_message( "Completed status: " . int($percent) . "%" ) if $percent < 100;
    }

    my %publish_data = ( 'publish_status' => 1, 'document_root' => $document_root, 'latest_publish_date' => time );
    $connector->cp_update_sitejet_metadata( $domain, \%publish_data );

    $connector->cp_save_tracking($domain);
    _cp_remove_obsolete_files( $domain, $connector->{config_dir} );

    if ( -e $Cpanel::API::NginxCaching::_nginx_installed_file ) {

        require Cpanel::API;
        my $api_result = Cpanel::API::execute( "NginxCaching", "clear_cache" );
        if ( !$api_result->{status} ) {
            log_message('Warning: unable to clear Nginx cache: $api_result->{errors}');
        }
    }
    log_message("Completed status: 100%");

    return 1;
}

=over

=item * fetchUrlsFromSitemap -- downloads sitemap file.

    The starting point for all publishing is the sitemap XML file.  This file
    contains a list of top-level files to be downloaded.  Those files will
    refer internally to other files to be downloaded, which in turn may refer
    to other files to be downloaded, and so on.  There is no depth limit.
    All assets for a complete website (html, images, scripts, styles, etc.)
    will be either be listed in this sitemap file or referred to indirectly.

    This method gets this initial list of files as URLs from the sitemap XML
    file.

    ARGUMENTS
        etag (string) -- Unique identifier

    RETURNS
        Reference to array that contains URL strings.

    ERRORS
        All failures are fatal.
        Fails if cannot contact Sitejet server.

    EXAMPLE
        my $urls = Cpanel::Sitejet::Publish::fetchUrlsFromSitemap($etag);

=back

=cut

sub fetchUrlsFromSitemap {
    my $orig_etag = shift;
    log_message( "Download sitemap xml:" . $origin . $PATH_SITEMAP );
    my ( $ua, $uri, $xml, $response, $current_etag );
    $ua = LWP::UserAgent->new();
    $ua->ssl_opts( verify_hostname => 1 );
    $uri = URI->new( $origin . $PATH_SITEMAP );
    $uri->query_form( { 'etag' => 'true' } );

    $response = $ua->get( $uri->as_string );
    $retry_attempts++;
    $current_etag = _get_etag($response);
    if ( _etag_mismatch( $orig_etag, $current_etag ) ) {
        log_message("fetchUrlsFromSitemap etag mismatch found. current etag : $current_etag expected_etag : $orig_etag ");
        if ( $retry_attempts >= 5 ) {
            die Cpanel::Exception::create( 'AdminError', 'The publish process did not update all required files. Please try the publish process again.' );
        }
        _sleep();
        return fetchUrlsFromSitemap($orig_etag);
    }

    if ( !$response->is_success ) {
        return;
    }
    my $sitemap_content = $response->content;
    $xml = Cpanel::XMLParser::XMLin($sitemap_content);
    my @urls = ();
    if ( ref $xml->{url} eq 'ARRAY' ) {
        foreach my $url ( @{ $xml->{url} } ) {
            push @urls, $url->{loc};
        }
    }
    elsif ( ref $xml->{url} eq 'HASH' ) {
        push @urls, $xml->{url}->{loc};
    }

    # store sitemap.xml
    my $full_schema_url = "https://$domain";
    $sitemap_content =~ s{$origin}{$full_schema_url}g;
    storeContent( $PATH_SITEMAP, $sitemap_content, 'application/xml' );

    return \@urls;
}

sub _sleep {
    sleep(5);
}

=over

=item * cleanup -- Backups/removes files that would be affected by new website.

    Only called the first time Sitejet publishes in a particular document
    root.

    ARGUMENTS
        none

    RETURNS
        1 if no errors.

    ERRORS
        All failures are fatal.
        Fails if cannot identify document root.

    EXAMPLE
        my $ok = Cpanel::Sitejet::Publish::cleanup();

=back

=cut

sub cleanup {
    my $homedir = $Cpanel::homedir;

    my ($target_folder) = $document_root =~ m{([^/]+)$};
    my $target_dir_name = $target_folder . '_' . time . '.gz';
    my $target_dir      = "$homedir/$target_dir_name";

    # get the first immediate folder name after doc root
    my @sub_docroots = map { m<$document_root/([^/\n]+)>; } keys %{ Cpanel::DomainLookup::getdocrootlist($Cpanel::user) };

    my @webdisks = Cpanel::WebDisk::api2_listwebdisks( home_dir => $homedir, );

    my @webdiskusers_docroots = map {
        $_->{homedir} =~ m<^$document_root/([^/]+)>;    # this one gives $1
    } @webdisks;
    my @dont_delete = ( @webdiskusers_docroots, @sub_docroots, '.well-known' );

    opendir my $dh, $document_root or do {
        warn("Cannot open directory: '$document_root'.");
        return;
    };

    # create .gz backup file in user home dir
    Cpanel::SafeRun::Errors::saferunallerrors( Cpanel::Tar::load_tarcfg()->{'bin'}, '-c', '-v', '-z', '-f', $target_dir, $document_root );

    # collect files to delete
    my @contents = grep { !/^\.\.?$/ } readdir($dh);

    # delete the files/dirs
    require Cpanel::SafeDir::RM;

    foreach my $content (@contents) {

        # exclude any immediate folders for webdisk & sub_docroots
        next if grep { $_ eq $content } @dont_delete;
        my $file = "$document_root/$content";
        -d $file ? Cpanel::SafeDir::RM::safermdir($file) : Cpanel::Autodie::unlink_if_exists($file);
    }

    return 1;
}

=over

=item * createFilename -- Creates local filenames

    Given a URL or relative filename returns a complete path filename for the
    local cPanel server.  For example, for cPanel user 'jim',
    'http://xyz.com/img.png' will be changed to '/home/jim/public_html/img.png'
    and 'smile.html' will be changed to '/home/jim/public_html/smile.html'.

    ARGUMENTS
        uri (string) -- Full URI or relative pathname for a file or directory
        mimeType (string, optional) -- Standard mime type of the file, something like 'text/html'

    RETURNS
        Full new local pathname (string)

    ERRORS
        All failures are fatal.
        URI is invalid.
        mime type is invalid.

    EXAMPLE
        my $fullname = Cpanel::Sitejet::Publish::createFilename($uri);

=back

=cut

sub createFilename {
    my ( $uri, $mimeType ) = @_;
    $uri = ( uri_split($uri) )[2];
    $uri = $uri =~ s{g/fonts/css}{g/fonts.css}gr;
    $uri =~ s{^/*(.*)/*$}{$1};    # trim '/'
    my $filename = File::Basename::basename($uri);
    if ( $filename eq './' ) {
        $filename = '';
    }

    my $path = $document_root . '/' . File::Basename::dirname($uri);
    $path     =~ s{/\.$}{};       # look for . directories
    $filename =~ s/\?.*$//;       # Strip off cgi params.

    if ( !$filename || $filename eq './' ) {
        $filename = 'index';
    }
    if ( $filename !~ $REGEX_FILE_EXT ) {
        my $extension = File::MimeInfo::extensions( $mimeType // 'text/html' );
        $extension = 'html' if $extension eq 'htm';
        if ( $extension eq 'html' && $filename ne 'index' ) {
            $path .= '/' . $filename;
            $filename = 'index';
        }

        $filename .= '.' . $extension;
    }

    $Cpanel::Sitejet::Connector::file_tracking{"$path/$filename"}++;
    return $path . '/' . $filename;
}

=over

=item * isBinary -- Is the string likely to be from a binary file

    This is intended to determine if a file (contained in $value as a string)
    is a binary file, such as an image.

    CURRENTLY THIS SUBROUTINE IS NOT USED ANYWHERE.  It was used only
    internally in conjunction with parseAndInstallLanguages(), but that is not
    used either yet.

    ARGUMENTS
        value (string) -- Any string

    RETURNS
        1 or empty string

    ERRORS
        Only fails if $value is undef.

    EXAMPLE
        my $bin = Cpanel::Sitejet::Publish::isBinary($value);

=back

=cut

sub isBinary {
    my ($value) = @_;
    return $value !~ /[\x00-\x08\x0B-\x0C\x0E-\x1F]/;
}

=over

=item * isStatic -- Identify files in certain paths that are considered static

    ARGUMENTS
        url (string) -- Path for a file or directory
        extended (boolean, optional) -- For some paths containing 'webcard', 'js', or 'css'

    RETURNS
        1 or empty string

    ERRORS
        $url is undef.

    EXAMPLE
        my $static = Cpanel::Sitejet::Publish::isStatic($url);
        my $ok     = Cpanel::Sitejet::Publish::isStatic( $url, $extended );

=back

=cut

sub isStatic {
    my ( $url, $extended ) = @_;
    my $ret =
         $url =~ m{^/(images|g|uploads)/[^"') ]+}
      || ( $extended && $url =~ m{/images/} )
      || ( $extended && $url =~ m{/webcard/} )
      || ( $extended && $url =~ m{^$origin/(js/custom\.js|css/custom\.css)} );

    return $ret // '';
}

=over

=item * log_message -- Send message to log file

    ARGUMENTS
        message (string) -- String to be logged

    RETURNS
        1 or empty string

    ERRORS
        $message is undef.
        $start global is undef.

    EXAMPLE
       Cpanel::Sitejet::Publish::log_message($message);

=back

=cut

sub log_message {
    my ($message) = @_;
    my $elapsed = time - $start;

    # Cpanel::Logger does not fail on disk quota exceeded.
    # The return status is the only way of knowing if the logger
    # failed to write.
    $logger->info("[$elapsed s] $message") or die Cpanel::Exception::create( 'IO::FileWriteError', [ 'error' => 'Cpanel::Logger failed to write the log.' ] );
}

=over

=item * parseAssets -- Search downloaded text assets for more assets

    Given a reference to an array of HTTP::Response assets, parse the content
    of each, looking for additional assets referred to.  Skips parsing non-text
    assets such as images.

    ARGUMENTS
        responses (array reference) -- HTTP::Response object for downloaded assets
        finishedUrls (array reference) -- Array contains URLs that have already been downloaded

    RETURNS
        Reference to array of strings, each containing a newly found asset url

    ERRORS
        $response is not an array of HTTP::Response object.
        $finishedUrls is not an array reference.

    EXAMPLE
        my $new_urls = Cpanel::Sitejet::Publish::parseAssets($responses, $finishedUrls);

=back

=cut

sub parseAssets {
    my ( $responses, $finishedUrls ) = @_;
    log_message('Parse assets from all responses that are not known binary formats');

    # SJ prevents filenames with certain chars like '%', ' ', or '/'.  This uri_unescape
    # converts encoded versions of them, and will process them individually in REGEX_ASSETS,
    # but it shouldn't matter, since SJ blocks them to begin with.
    my $all_responses = URI::XSEscape::uri_unescape( join "\n", map { $_->headers->{'content-type'} !~ m{^(image|video|audio)/|(application/octet-stream)}n ? $_->content : '' } @$responses );
    $all_responses =~ s/&quot;/"/g;

    # foreign characters and dots pass through
    # spaces and quotes are cut off
    my @hits        = $all_responses =~ /($REGEX_ASSETS)/g;
    my %seen        = ();
    my @unique_urls = grep { !$seen{$_}++ } @hits;

    my @urls;

    # Do not process already processed urls
    foreach my $url (@unique_urls) {
        if ( !grep /^\Q$origin$url\E$/, @$finishedUrls ) {
            push @urls, $url;
        }
    }

    my @more_urls = @urls;

    # detect images that are downloaded as originals
    # for which thumb urls might be generated dynamically
    foreach my $url (@urls) {

        # /images/0/2437851/pexels-photo-1139793.jpg
        if ( $url =~ m{/0/} ) {
            push @more_urls, $url =~ s{/0/}{/1920/}r;
            push @more_urls, $url =~ s{/0/}{/1024/}r;
        }

        # /images/0%2C2249x1416%2B0%2B83/2437401/pexels-photo-356378.jpg
        if ( $url =~ m{/0,} ) {
            push @more_urls, $url =~ s{/0,}{/1920,}r;
            push @more_urls, $url =~ s{/0,}{/1024,}r;
            push @more_urls, $url =~ s{/0,[^/]*}{/1920}r;
            push @more_urls, $url =~ s{/0,[^/]*}{/1024}r;
        }

        # /images/0_2249x1416_0_83/2437401/pexels-photo-356378.jpg
        if ( $url =~ m{/0_} ) {
            push @more_urls, $url =~ s{/0_}{/1920_}r;
            push @more_urls, $url =~ s{/0_}{/1024_}r;

            # URL encoded + , x NaN
            push @more_urls, $url =~ s{/0[_0-9x]+/}{/1920/}r;
            push @more_urls, $url =~ s{/0[_Na0-9x]+/}{/1024/}r;
        }
    }

    my @js_chks = $all_responses =~ /$REGEX_JS_CHUNKS/gm;
    push @more_urls, grep { length } map { $_ = '/webcard/static/' . $_ . '.js' if !m{/?webcard/static/}; } @js_chks;

    # parse xml for RSS feeds
    my @xml = $all_responses =~ /$REGEX_RSS/igm;
    push @more_urls, @xml;

    my %unique_urls = map { $_ => 1 } @more_urls;
    @more_urls = keys %unique_urls;

    return \@more_urls;
}

# Original Plesk subroutine.  We're not using this.
# sub parseAndInstallLanguages {}

=over

=item * executeRequests -- Fetch asset

    Downloads an asset described by URL.

    ARGUMENTS
        url (string) -- Fully qualified URL

    RETURNS
        Reference to HTTP::Response object

    ERRORS
        $url is invalid

    EXAMPLE
        my $response = Cpanel::Sitejet::Publish::executeRequests($url);

=back

=cut

sub executeRequests {
    my $url = shift;
    log_message("Prepare request for $url");
    my %headers = (
        'User-Agent' => 'Sitejet API Client/1.0.0 (Perl ' . $^V . ')',
        'Connection' => 'Close',
        'Accept'     => 'application/json'
    );
    my $ua = LWP::UserAgent->new(
        timeout  => 30,
        ssl_opts => { verify_hostname => 1 },
    );

    my $response = $ua->get( $url, %headers );

    log_message( "URI: '$url', " . $response->code );

    return $response;
}

=over

=item * processResponse -- process HTTP::Response for asset

    Process includes validating and saving as a local file.

    ARGUMENTS
        response (HTTP::Response object) -- Result of fetching asset using executeRequest()
        uri (string) -- The same URI used when the asset was fetched

    RETURNS
        Content string from HTTP::Response object

    ERRORS
        Saving local copy of file error--bad filename, no disc space, no permission, etc.

    EXAMPLE
        my $file_contents = Cpanel::Sitejet::Publish::processResponse( $response, $uri, );

=back

=cut

sub processResponse {
    my ( $response, $uri ) = @_;

    log_message("Process response of $uri");

    if ( !$response->is_success ) {
        return '';
    }

    my $content = $response->content;
    my $headers = $response->headers->as_string;

    my $body        = $content;
    my $contentType = $response->header('Content-Type');
    my ($mimeType)  = $contentType =~ /^([^;]*);?/;

    foreach my $host (@CDN_HOSTS) {
        $body =~ s/\Q$host\E//g;
    }

    storeContent( $uri, $body, $mimeType );

    return $body;
}

=over

=item * storeContent -- save asset as a file

    Given a URI, the contents of the file, and the mime type, determines the
    filename, path, and extension to save as.  And saves it.

    ARGUMENTS
        uri (string) -- The same URI used when the asset was fetched
        body (string) -- contents of the file, obtained through HTTP::Response content field
        mimeType (string) -- Something like 'text/html' or 'image/png'

    RETURNS
        body (contents of file as a string)

    ERRORS
        Saving local copy of file error--bad filename, no disc space, no permission, etc.

    EXAMPLE
        my $body = Cpanel::Sitejet::Publish::storeContent( $uri, $body, $mimeType );

=back

=cut

sub storeContent {
    my ( $uri, $body, $mimeType ) = @_;

    log_message("Store content for $uri");

    my $filename = createFilename( $uri, $mimeType );
    my $path     = File::Basename::dirname($filename);

    if ( !-e $path ) {
        log_message("Create directory $path");
        File::Path::make_path( $path, { mode => 0755 } );
    }

    my $bodyToStore = $body;
    $bodyToStore =~ s{g/fonts/css}{g/fonts.css}g;
    $bodyToStore =~ s{<meta name="robots" content="none" />}{}g;

    # including quotes in case host is mentioned somewhere else
    # this will resolve location.host in run time js.
    $bodyToStore =~ s{'api.sitehub.io'}{location.host + '/api.php'}g;

    # replace preview url
    my $protocol_to_store = $ssl_status ? 'https://' : 'http://';
    $bodyToStore =~ s{$origin}{$protocol_to_store$domain}g;

    log_message("Save file $filename");
    open my $fh, '>', $filename or Cpanel::Exception::create( "IO::FileOpenError", [ path => $filename, error => $! ] );
    print $fh $bodyToStore;
    close $fh;

    return $body;
}

=over

=item * cp_process_sitemap -- Build URL for sitemap.XML, download it and return URLs from it.

    Given a URI, the contents of the file, and the mime type, determines the
    filename, path, and extension to save as.  And saves it.

    Please note that the global, $document_root, will need to be given a value
    *before* calling this subroutine.

    ARGUMENTS
        connector -- Cpanel::Sitejet::Connector object
        domain (string) -- Something like 'xyz.com'

    RETURNS
        Reference to array of URL strings from sitemap XML file
        etag (string) for site

    ERRORS
        All errors are fatal.
        File system error due to no permissions, no space on disc, etc.
        Unable to acquire sitemap XML file
        Domain invalid
        Cannot obtain site API key
        Cannot obtain website preview URL

    EXAMPLE
        $document_root = _get_document_root($domain);
        my $connector = Cpanel::Sitejet::Connector->new();
        my ( $urls, $etag ) = Cpanel::Sitejet::Publish::cp_process_sitemap( $connector, $domain );

=back

=cut

sub cp_process_sitemap {
    my ( $connector, $domain ) = @_;

    my $path = $document_root;
    if ( !-e $path ) {
        Cpanel::Autodie::mkdir_if_not_exists( $path, 0755 );
    }
    my $chdir       = Cpanel::Chdir->new($path);
    my $token       = $connector->loadApiKey();
    my $previewData = $connector->getPreviewDataForWebsite( $domain, $token );
    my $sitemap_url = $previewData->{url};

    if ( $sitemap_url !~ /^http/i ) {
        $sitemap_url = 'https://' . $sitemap_url;
    }

    $origin = $sitemap_url;
    my $etag = $previewData->{etag};

    my $urls = fetchUrlsFromSitemap($etag);
    if ( !$urls ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Unable to obtain URLs from sitemap at “[_1]”.', [$sitemap_url] );
    }

    return ( $urls, $etag );
}

sub _mark_processed ($url) {
    log_message("Done processing $url");
    $processed_urls{$url} = 1;
}

sub _is_static ($url) {

    # skip /webcard/static/ folder
    return 1 if $url =~ m{^/webcard/static/$};
    if ( isStatic($url) ) {
        if ( $url =~ /^(\S*)\s/ ) {
            $url = $1;
        }
        my $this_file = createFilename($url);
        if ( -e $this_file ) {
            log_message("$url already downloaded");
            return 1;
        }
    }

    return 0;
}

sub _is_latest ( $url, $etag, $response ) {

    # Validate ETag for non-static pages
    if ( $etag && !isStatic( $url, 1 ) ) {
        my $parsedEtag = _get_etag($response);
        if ( _etag_mismatch( $etag, $parsedEtag ) ) {
            log_message("etag mismatch found.  uri : $url current etag: $parsedEtag  expected etag : $etag ");
            return 0;
        }
    }
    return 1;
}

sub _fetch_one_file ( $url, $etag, $connector ) {

    # skip if already downloaded and isStatic
    return 1 if _is_static($url);

    # add full schema
    $url = _add_url_origin($url);

    # an additional check to avoid duplication
    return 1 if $processed_urls{$url};

    my $response = executeRequests($url);
    return 0 if !_is_request_success($response);
    return 0 if !_is_latest( $url, $etag, $response );

    my $asset_urls = _process_one_file( $url, $response, $connector );

    foreach my $asset_url (@$asset_urls) {
        _fetch_one_file_with_retry( $asset_url, $etag, retry_limit(), $connector );
    }
    return 1;
}

sub _process_one_file ( $url, $response, $connector ) {

    my $content = processResponse( $response, $url );

    _mark_processed($url);

    parseAndInstallLanguages( $content, $connector ) if !$language_set;

    return parseAssets( [$response], [ keys %processed_urls ] );
}

sub _fetch_one_file_with_retry ( $url, $etag, $retry_limit, $connector ) {
    my $tries = 0;
    while ( $tries < $retry_limit ) {
        return if _fetch_one_file( $url, $etag, $connector );
        $tries++;
        _sleep();
    }
    log_message("Reached max retry limit: Processing $url as it is.");
}

sub _add_url_origin {
    my $url = shift;
    if ( isStatic($url) ) {
        $url = 'https://inter-cdn.com/' . $url;
    }
    else {
        if ( $url !~ /^http/i ) {
            $url = $origin . '/' . $url;
        }
    }
    $url =~ s{(?<!http:|https:)//}{/}g;
    return $url;
}

sub _etag_mismatch {
    my ( $source_etag, $current_etag ) = @_;
    return ( $current_etag && ( $source_etag ne $current_etag ) ) ? 1 : 0;
}

sub _get_etag {
    my $response   = shift;
    my $parsedEtag = $response->header('etag');
    $parsedEtag =~ s/\"//g if $parsedEtag;
    return $parsedEtag;
}

sub _is_request_success ($response) {
    return 0 if !$response->is_success;
    return 1;
}

sub get_document_root {
    my $domain   = shift;
    my $docroots = Cpanel::DomainLookup::DocRoot::getdocroots($Cpanel::user);
    if ( exists $docroots->{$domain} ) {
        return $docroots->{$domain};
    }
    return;
}

sub parseAndInstallLanguages ( $content, $connector ) {
    my @languages;
    my $pos = 0;
    while ( ( $pos = index( $content, '<link rel="alternate" hreflang="', $pos ) ) > 0 ) {
        $pos += 32;
        push @languages, substr( $content, $pos, 2 );
    }
    $connector->installLanguages( $document_root, @languages ) if @languages > 0;
    $connector->cp_update_sitejet_metadata( $domain, { 'multi_language' => join( ",", @languages ) } );
    $language_set = 1;
    return;
}

# Gets rid of obsolete files from a previous publish().
sub _cp_remove_obsolete_files {

    my ( $domain, $config_dir ) = @_;

    my @old_files = ();

    #  If there was a previous publish(), the list of tracked files should be in ~/.cpanel/sitejet/<domain>-files.
    my $old_tracking = "$config_dir/$domain-files";
    if ( -e $old_tracking ) {
        open my $fh_old, "<", $old_tracking or Cpanel::Exception::create( "IO::FileReadError", [ path => $old_tracking, error => $! ] );
        chomp( @old_files = <$fh_old> );
        close $fh_old;
    }

    #  Gives us files only in ~/.cpanel/sitejet/<domain>-files.  These are the obsolete files that need to be removed.
    my @obsolete = grep { !exists $Cpanel::Sitejet::Connector::file_tracking{$_} } @old_files;

    unlink @obsolete;

    cp_remove_unused_directories( $domain, @obsolete );

    rename "$config_dir/$domain-files_new", $old_tracking;

    return;
}

=over

=item * cp_remove_unused_directories -- Given a list of paths, remove all the empty directories.

    Given a list of files and/or directories, remove any empty directories.
    Traverses from the bottom up for each path passed in removing directories
    until it finds a non-empty directory.  Finding a non-empty directory will
    terminate the traversal on that path.  Stops at $document_root and will not
    remove that.

    Domain is passed in, just in case the global, $document_root, was not set
    *before* calling this subroutine.

    ARGUMENTS
        domain (string) -- Something like 'xyz.com'
        paths (array) -- Array of paths to be checked for empty directories

    RETURNS
        undef

    ERRORS
        Fatal - document root was not set

    EXAMPLE
        Cpanel::Sitejet::Publish::cp_remove_unused_directories( $domain, @paths );

=back

=cut

sub cp_remove_unused_directories {
    my ( $domain, @paths ) = @_;

    $document_root = get_document_root($domain) if !$document_root;

    do {
        # Strips off filename or '/', leaving the directory.  Hash gives unique list of directories.
        my %dirs = map { s!(^.*)/[^/]*$!$1!; $_ => 1 } @paths;
        @paths = grep { $_ ne $document_root } keys %dirs;    # Not interested in removing document root.

        foreach (@paths) {

            # Fails if directory not empty.  In that case we don't need it in @paths.
            rmdir or undef $_;
        }
        @paths = grep { defined } @paths;
    } while (@paths);

    return;
}

1;
