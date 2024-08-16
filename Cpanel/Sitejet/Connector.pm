package Cpanel::Sitejet::Connector;

# cpanel - Cpanel/Sitejet/Connector.pm             Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::DomainLookup::DocRoot();
use Cpanel::Exception;
use Cpanel::JSON();
use Cpanel::Logger;
use File::Path();
use LWP::UserAgent;
use Umask::Local();

use constant {
    API_HOST             => 'https://api.sitehub.io',
    _ENOENT              => 2,
    CREATE_ACCOUNT_TOKEN => '82b9c2a6422a1dc46b3e03126fd4da8f',
    DEFAULT_LIGHT_SVG    => '/usr/local/cpanel/base/frontend/jupiter/sitejet/assets/Site_Builder_Light.svg',
    DEFAULT_DARK_SVG     => '/usr/local/cpanel/base/frontend/jupiter/sitejet/assets/Site_Builder_Dark.svg',
    API_PHP_TMPL         => '/var/cpanel/plugins/sitejet/resources/api.php.tmpl',
    FLAGS_ZIP            => '/var/cpanel/plugins/sitejet/resources/flags.tar.gz',
};

our %file_tracking;

=encoding utf-8

=head1 NAME

Cpanel::Sitejet::Connector

=head1 DESCRIPTION

Helper module for Cpanel::Sitejet::Publish.  This module handles connections
between cPanel server and Sitejet's servers.

This module matches Plesk's SitejetConnector.php in the sitejet-plesk repo. The
names of subroutines and variables in Perl match as much as possible, so that
future changes can be easily replicated.

The Plesk PHP naming convention for subroutines and variables is camelCase, so
their counterparts in this cPanel module match.

The cPanel standard naming convention is snake_case, except for module names
which are camelCase. Any subroutine or variable that is named using snake_case
does NOT have a corresponding PHP equivalent in the Plesk source code.

Subroutines whose name begins with "cp_" have no corresponding subroutine in
the original Plesk PHP source code. "cp_" just indicates the subroutine
originated with cPanel.

=cut

=head1 METHODS

=over

=item * new -- Create Connector object.

    ARGUMENTS
        None

    RETURNS
        Cpanel::Sitejet::Connector object

    ERRORS
        None

    EXAMPLE
        my $conn_obj = Cpanel::Sitejet::Connector::new();

=back

=cut

sub new {
    my $class = shift;

    %file_tracking = ();

    my $self   = { config_dir => "$Cpanel::homedir/.cpanel/sitejet" };
    my $logger = Cpanel::Logger->new();
    $self->{'logger'} = $logger;

    _check_domain_config();
    return bless $self, $class;
}

=over

=item * accountExists -- Find out if cPanel user has ever used Sitejet.

    This method relies on the cPanel user file in /var/cpanel/users/<user> to
    have the field SITEJET_API_TOKEN to determine if a cPanel user has ever
    used Sitejet.

    ARGUMENTS
        None

    RETURNS
        1 if cPanel account has used Sitejet
        0 if cPanel account has not used Sitejet

    ERRORS
        All failures are fatal.
        Fails if cannot access cPanel user info.

    EXAMPLE
        my $hasSitejetAccount = Cpanel::Sitejet::Publish::accountExists();

=back

=cut

sub accountExists {
    require Cpanel::Config::LoadCpUserFile;
    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($Cpanel::user);
    return exists $cpuser_ref->{SITEJET_API_TOKEN} ? 1 : 0;

    #    return Modules::PleskSitejet::SitejetConnector::Settings::get(SETTING_API_KEY);
}

# Original Plesk subroutine.  We're not using this.
# sub sync{}

=over

=item * createAccount -- create new Sitejet account for current cPanel user

    ARGUMENTS
        None

    RETURNS
        Hash reference to API key as follows:

        $ret = { 'key' => '5164dad7c25e986ba6235a61c7448f62' };

    ERRORS
        All failures are fatal.
        Fails if cPanel user already has a Sitejet account.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $key = $conn_obj->createAccount();

=back

=cut

sub createAccount {
    my ($self) = @_;
    require Cpanel::Config::LoadCpUserFile;

    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($Cpanel::user);
    if ( exists $cpuser_ref->{SITEJET_API_TOKEN} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Sitejet account already exists for user: “[_1]”.', [$Cpanel::user] );
    }
    my $uuid = exists $cpuser_ref->{'UUID'} ? $cpuser_ref->{'UUID'} : '';

    my $ret = $self->request( 'post', '/cpanel/account', CREATE_ACCOUNT_TOKEN, { license => $uuid } );

    return $ret;

}

=over

=item * createWebsite -- create new Sitejet website

    ARGUMENTS
        $website_info_hr (hash reference) -- Contains website info as described in example below.

    RETURNS
        website_id (string)

    ERRORS
        All failures are fatal.
        Fails if cannot get websiteId.

    EXAMPLE
        my %website_info = (
            company          => 'Fezzik, Inc.',
            cpanelDomainGUID => 'inconceivable.com',
            document_root    => "/home/fezzik/public_html",
            domain           => 'inconceivable.com',
            fullcms          => 1,
            language         => 'en',
            publish_status   => 1,
            templateId       => "377388",
            websiteId        => 395309,
        );
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $website_id = $conn_obj->createWebsite( \%website_info );

=back

=cut

sub createWebsite {
    my ( $self, $website_info_hr ) = @_;

    my $api_token = $self->loadApiKey();
    delete @$website_info_hr{ grep { !defined $website_info_hr->{$_} } keys %$website_info_hr };

    my $ret = $self->request( 'post', '/website', $api_token, $website_info_hr );
    if ( !defined $ret || !exists $ret->{websiteId} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Unable to obtain websiteId for domain: “[_1]”.', [ $website_info_hr->{domain} ] );
    }
    my $website_id = $ret->{websiteId};
    require Cpanel::Sitejet::Publish;
    my $document_root = Cpanel::Sitejet::Publish::get_document_root( $website_info_hr->{domain} );
    $website_info_hr->{document_root} = $document_root;
    $self->storeWebsiteId( $website_info_hr, $website_id );

    return $website_id;
}

=over

=item * selectTemplateForWebsite -- Sets and stores the cPanel user's chosen template on cPanel and Sitejet servers

    ARGUMENTS
        domain (string) -- Domain name of this website
        templateId (string) -- Unique identifier for chosen template
        templateName (string) -- The name of the chosen template

    RETURNS
        Reference to hash:
            { "success" => $bool_obj }
        Where $bool_obj is a JSON::PP::Boolean object that contains a 1 for
        success.  If it fails, then you won't get this at all.  You'll get an
        exception instead.

    ERRORS
        All failures are fatal.
        Fails if domain is not correct.
        Fails if templateId is not correct.
        Fails if cannot get websiteId or API token.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $ret = $conn_obj->selectTemplateForWebsite( $domain, $templateId, $templateName );

=back

=cut

sub selectTemplateForWebsite {
    my ( $self, $domain, $templateId, $templateName ) = @_;

    my $websiteId = $self->getWebsiteIdForDomain($domain);

    my $api_token = $self->loadApiKey();
    my $ret       = $self->request( 'post', "/website/${websiteId}/template/${templateId}", $api_token );
    $self->storeWebsiteTemplateId( $domain, $templateId, $templateName );

    return $ret;
}

=over

=item * getSSOLinkForWebsite -- Gets SSO link

    ARGUMENTS
        A hash reference of arguments.
        domain (string) -- Domain name of this website
        referrer (string) -- Path to current webpage
        locale (string) -- Standard locale string something like 'en'
        company_id (integer) -- The companyID provided by the License

    RETURNS
        SSOLink URL (string)

    ERRORS
        All failures are fatal.
        Fails if domain is not correct.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $SSOLink = $conn_obj->getSSOLinkForWebsite( $domain, $referrer, 'en', 7 );

=back

=cut

sub getSSOLinkForWebsite {

    my ( $self, $args ) = @_;

    my $domain    = $args->{'domain'};
    my $websiteId = $self->getWebsiteIdForDomain($domain);
    eval { $self->cp_update_logo($domain); };
    $self->{logger}->warn("Unable to update logo due to the following exception $@") if $@;
    my $apiKey = $self->loadApiKey();

    require Whostmgr::API::1::Utils::Execute;
    my $result           = Whostmgr::API::1::Utils::Execute::execute_or_die( 'Sitejet', "get_ecommerce" );
    my $ecommerce_status = $result->{data}{is_enabled};
    my $storeUrl         = $ecommerce_status ? ( $result->{data}{storeurl} // '' ) : '';

    my $ret = $self->request(
        'get',
        "/website/$websiteId/sso",
        $apiKey,
        {
            'route'           => 'my_website_cms',
            'dom_id'          => $domain,
            'referer'         => $args->{referrer},
            'language'        => $args->{locale},
            'company_id'      => $args->{company_id},
            'ecommerce'       => $ecommerce_status,
            'ecommerceBuyUrl' => $storeUrl,
        }
    );

    if ( !defined $ret ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Failed to get SSO link for domain: “[_1]”.', [$domain] );
    }

    return $ret;
}

=over

=item * cp_getPreviewUrlPart -- Returns preview URL path

    Note:  It will return a bad path if websiteID is wrong or empty.

    ARGUMENTS
        websiteId (string) -- Unique website ID

    RETURNS
        Website preview path (string)

    ERRORS
        None.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $path = $conn_obj->cp_getPreviewUrlPart( $websiteId );

=back

=cut

sub cp_getPreviewUrlPart {
    my ( $self, $websiteId ) = @_;

    return "/website/$websiteId/previewurl";
}

=over

=item * cp_getPreviewUrl -- Returns preview URL

    Note:  It will return a bad URL if websiteID is wrong or empty.

    ARGUMENTS
        websiteId (string) -- Unique website ID

    RETURNS
        Website preview URL (string)

    ERRORS
        None.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $path = $conn_obj->cp_getPreviewUrlPart( $websiteId );

=back

=cut

sub cp_getPreviewUrl {
    my ( $self, $websiteId ) = @_;

    return API_HOST . $self->cp_getPreviewUrlPart($websiteId);
}

=over

=item * getPreviewDataForWebsite -- Preview URL and ETag

    ARGUMENTS
        domain (string) -- Domain name of this website
        apiKey (string) -- Unique API key

    RETURNS
        Reference to hash with keys for 'url' and 'etag', like this:
            {
              'url' => '1fb26b-5f3aa.preview.sitehub.io',
              'etag' => 'fb8cfc2196419f23ec2a53ea3cd77fea'
            };

    ERRORS
        All errors are fatal.
        Fatal if domain or API key are wrong.
        Fatal if cannot connect to Sitejet server.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $path = $conn_obj->getPreviewDataForWebsite( $domain, $apiKey );

=back

=cut

sub getPreviewDataForWebsite {
    my ( $self, $domain, $apiKey ) = @_;
    my $websiteId = $self->getWebsiteIdForDomain($domain);
    my $urlpart   = $self->cp_getPreviewUrlPart($websiteId);

    my $ret = $self->request( 'get', $urlpart, $apiKey, { 'etag' => 'true' } ) or die Cpanel::Exception::create( 'InvalidParameter', 'Cannot get preview.' );
    return $ret;
}

=over

=item * getWebsiteIdForDomain -- Gets the unique website identifier for a specific domain

    ARGUMENTS
        domain (string) -- Domain name of this website

    RETURNS
        websiteId (string) -- Unique website ID

    ERRORS
        All errors are fatal.
        Fatal if domain or API key are wrong.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $path = $conn_obj->getWebsiteIdForDomain($domain);

=back

=cut

sub getWebsiteIdForDomain {
    my ( $self, $domain ) = @_;
    my $user_metadata = $self->cp_load_sitejet_metadata($domain);
    if ( !defined $user_metadata || !exists $user_metadata->{websiteId} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Unable to obtain websiteId for domain: “[_1]”.', [$domain] );
    }

    my $webid = $user_metadata->{websiteId};

    # Original Plesk vars
    # return $domain->getSetting(SETTING_WEBSITE_ID);
    return $webid;
}

=over

=item * storeWebsiteId -- Saves websiteId to file.

    Inserts websiteId into $website_info hash and saves in the cPanel user's local
    directory at $Cpanel::homedir/.cpanel/sitejet/<domain> in JSON format.

    ARGUMENTS
        $website_info (hash reference) -- Contains website info as described in example below.
        website_id (string)

    RETURNS
        None

    ERRORS
        All errors are fatal.
        Fatal if websiteId or website_info are missing.

    EXAMPLE
        my %website_info = (
            company          => 'Fezzik, Inc.',
            cpanelDomainGUID => 'inconceivable.com',
            document_root    => "/home/fezzik/public_html",
            domain           => 'inconceivable.com',
            fullcms          => 1,
            language         => 'en',
            publish_status   => 1,
            templateId       => "377388",
            templateName     => 'A great template',
            websiteId        => 395309,
        );
        my $conn_obj = new Cpanel::Sitejet::Connector;
        $conn_obj->storeWebsiteId( \$website_info, $websiteId );

=back

=cut

sub storeWebsiteId {
    my ( $self, $website_info, $website_id ) = @_;
    $website_info->{websiteId} = $website_id;

    Cpanel::SafeDir::MK::safemkdir_or_die( $self->{config_dir}, 0700 );
    my $filename = $self->{config_dir} . '/' . $website_info->{domain};
    $self->cp_write_json( $filename, $website_info );

    return;
}

# Original Plesk subroutine.  We're not using this.
# sub getWebsiteTemplateIdForDomain{}

=over

=item * storeWebsiteTemplateId -- Saves websiteTemplateId to file.

    Saves website's templateId in the cPanel user's local directory at
    $Cpanel::homedir/.cpanel/sitejet/<domain> in JSON format among other website
    information in that file.

    ARGUMENTS
        domain (string) -- Domain name of this website
        templateId (string) -- Unique identifier for chosen template
        templateName (string) -- The name of the chosen template

    RETURNS
        None

    ERRORS
        All errors are fatal.
        Fatal if cannot read or write to cPanel user's Sitejet info file.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        $conn_obj->storeWebsiteTemplateId( $domain, $templateId, $templateName );

=back

=cut

sub storeWebsiteTemplateId {
    my ( $self, $domain, $templateId, $templateName ) = @_;
    my $filename     = "$self->{config_dir}/$domain";
    my %website_info = $self->cp_read_json($filename);
    $website_info{templateId}   = $templateId;
    $website_info{templateName} = $templateName;

    $self->cp_write_json( $filename, \%website_info );

    return;
}

# Original Plesk subroutine.  We're not using this.
# sub storeApiKey{}

=over

=item * loadApiKey -- Retrieve API token for this cPanel user

    Extracts and returns SITEJET_API_TOKEN field from the cPanel user file
    located in /var/cpanel/users/<cpanel-user>.

    Assumes $Cpanel::user is set to the appropriate cPanel user.

    ARGUMENTS
        None.

    RETURNS
        Sitejet API token (string)

    ERRORS
        All errors are fatal.
        Fatal if cannot read the cPanel user file.
        Fatal if cPanel user does not have SITEJET_API_TOKEN in cPanel user file.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $api_token = $conn_obj->loadApiKey();

=back

=cut

sub loadApiKey {
    my $self = shift;
    require Cpanel::Config::LoadCpUserFile;
    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($Cpanel::user);
    my $token      = $cpuser_ref->{'SITEJET_API_TOKEN'} or die Cpanel::Exception::create( 'EntryDoesNotExist', 'No Sitejet API token found for user “[_1]”.', [$Cpanel::user] );

    return $token;
}

=over

=item * request -- Wrapper around an HTTP Request

    ARGUMENTS
        method (string) - 'GET' or 'POST'
        endpoint (string) - URL path portion, something like '/template'
        apiKey (string) - API token from cPanel user file
        data (string) - Optional

    RETURNS
        server response -- can be array reference, string, or hash reference

    ERRORS
        Fatal if response status is anything other than 200.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $template_ref = $conn_obj->request( 'get', '/v1/templates', $api_token );

=back

=cut

sub request {
    my ( $self, $method, $endpoint, $apiKey, $data ) = @_;

    my $url = API_HOST . $endpoint;

    my %headers = (
        'User-Agent'  => 'Sitejet API Client/1.0.0 (Perl ' . $^V . ')',
        'Connection'  => 'Close',
        'Accept'      => 'application/json',
        'X-Api-Token' => $apiKey,
    );
    my $ua = LWP::UserAgent->new(
        timeout  => 30,
        ssl_opts => { verify_hostname => 1 },
    );
    my ( $response, $uri );

    if ( defined $data && $endpoint eq '/account' ) {
        $uri      = URI->new($url);
        $response = $ua->$method(
            $uri->as_string,
            %headers,
            'Content_Type' => 'multipart/form-data',
            'Content'      => {
                'partner_edit[editorLogoLight]' => $data->{LogoLight},
                'partner_edit[editorLogoDark]'  => $data->{LogoDark}
            },
        );
    }
    elsif ( defined $data ) {
        $uri = URI->new($url);
        $uri->query_form($data);
        $response = $ua->$method(
            $uri->as_string,
            %headers,
        );
    }
    else {
        $response = $ua->$method(
            $url,
            %headers
        );
    }

    my $status = $response->code;
    if ( $status != 200 ) {
        if ( !$response->is_success ) {
            die Cpanel::Exception::create( 'FeatureNotEnabled', 'The API call failed with error code “[_1]” and response “[_2]”.', [ $response->{_rc}, $response->{_content} ] );
        }
    }

    return $self->cp_read_json($response);
}

# PHP handleApiException() removed since exceptions are handled by Cpanel::Exception::create().

=over

=item * cp_load_sitejet_metadata -- Loads sitejet metadata from file.

    Loads cPanel user's Sitejet website info from file at
    $Cpanel::homedir/.cpanel/sitejet/<domain> where it is stored in JSON format.

    ARGUMENTS
        domain (string) -- Domain name of the website

    RETURNS
        Reference to hash containing all the fields something like this:
        my $website_info = {
            domain           => 'inconceivable.com',
            company          => 'Fezzik, Inc.',
            title            => undef,
            firstname        => undef,
            lastname         => undef,
            street           => undef,
            zip              => undef,
            city             => undef,
            country          => undef,
            language         => 'en',
            email            => undef,
            phone            => undef,
            note             => undef,
            metadata         => undef,
            assignTo         => undef,
            fullcms          => 1,
            cpanelDomainGUID => 'inconceivable.com',
        };

    ERRORS
        Fatal if file does not exist.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $website_info = $conn_obj->cp_load_sitejet_metadata($domain);

=back

=cut

sub cp_load_sitejet_metadata {
    my ( $self, $domain ) = @_;
    my %ret;
    eval { %ret = $self->cp_read_json("$self->{config_dir}/$domain"); };
    if ( $@ && $@ !~ /No such file or directory/ ) {

        # TODO: DUCK-9294
        # Added logger in IDUCK-9325 story.
        # Will add the logger to send info when this is merged.
        # using regular warn for now
        warn $@;
    }
    return \%ret;
}

=over

=item * cp_load_all_sitejet_domains_metadata -- Loads all Sitejet websites' metadata from files.

    Loads metadata for each Sitejet website for the current cPanel user
    ($Cpanel::user) from info in the files located in the user's ~/sitejet/
    directory.

    ARGUMENTS
        None.

    RETURNS
        A hash references to each Sitejet website's metadata.

    ERRORS
        Fatal if cannot get document roots for each website.
        Fatal if cannot read the Sitejet website files or directory.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $all_websites_info = $conn_obj->cp_load_all_sitejet_domains_metadata();

=back

=cut

sub cp_load_all_sitejet_domains_metadata {
    my ($self) = @_;
    require Cpanel::DomainLookup::DocRoot;

    my $known_user_domains_hr = Cpanel::DomainLookup::DocRoot::getdocroots($Cpanel::user);

    # Read files for a list of Sitejet domains for the cPanel user
    opendir my $dh, "$self->{config_dir}" or do {
        return if $! == _ENOENT();
        warn("Cannot open directory: $self->{config_dir}. $!");
    };
    my @list_files = grep { !/^\.\.?$/ } readdir($dh);

    my @sj_files = map { "$self->{config_dir}/" . $_ } grep { $known_user_domains_hr->{$_} } @list_files;

    # Get all cPanel user Sitejet domain metadata, sort by website ID
    my @read_sites_data;
    my $result;
    for my $filename (@sj_files) {
        my %res = $self->cp_read_json($filename);
        $result->{ $res{'domain'} } = \%res;
    }

    return $result;
}

=over

=item * cp_update_sitejet_metadata -- Update Sitejet website metadata file.

    Loads metadata from Sitejet website file, updates passed in fields and
    saves back in the file located in the $Cpanel::homedir/.cpanel/sitejet/ directory.

    ARGUMENTS
        domain (string) -- Domain name of the website
        data -- Hash reference containing just the fields (keys/values) to be updated

    RETURNS
        1

    ERRORS
        Fatal if cannot read or write the Sitejet website file or directory.

    EXAMPLE
        my $domain = 'inconceivable.com';
        my $data = {
            company          => 'Buttercup, Inc.',
            language         => 'fr',
        };
        my $conn_obj = new Cpanel::Sitejet::Connector;
        $conn_obj->cp_update_sitejet_metadata( $domain, $data);

=back

=cut

sub cp_update_sitejet_metadata {
    my ( $self, $domain, $data ) = @_;
    my $filename = "$self->{config_dir}/$domain";
    my %website_info;
    if ( !-e $filename ) {
        Cpanel::SafeDir::MK::safemkdir_or_die( $self->{config_dir}, 0700 ) if !-d $self->{config_dir};
    }
    else {
        %website_info = $self->cp_read_json($filename);
    }
    foreach my $key ( keys %$data ) {
        $website_info{$key} = $data->{$key};
    }

    $self->cp_write_json( $filename, \%website_info );

    return 1;
}

=over

=item * cp_get_templates -- Get Sitejet website templates data.

    ARGUMENTS
        domain (string) -- Domain name of the website
        data -- Hash reference containing just the fields (keys/values) to be updated

    RETURNS
        Reference to array of anonymous hashes containing template data that
        looks something like this:
        $all_templates = [
            {
                "createdAt"   : "2023-03-18T10:01:02+01:00",
                "description" : "",
                "id"          : 371507,
                "image"       : "/images/1024/6687284/OG_Image_Drive.png",
                "name"        : "Drive",
                "previewUrl"  : "https://www.template-drive.de.rs",
                "tags"        : [
                    "onepager",
                    "new",
                    "services"
                ],
                "updatedAt" : "2023-07-03T16:22:12+02:00"
            },
            ...
        ];

    ERRORS
        Fatal if cannot load API token.
        Fatal if cannot access Sitejet template server.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $all_templates = $conn_obj->cp_get_templates();

=back

=cut

sub cp_get_templates {
    my $self = shift;

    my $api_token = $self->loadApiKey();

    my $template_ref = $self->request( 'get', '/v1/templates', $api_token );

    return $template_ref;
}

=over

=item * cp_list_all_domain_sitebuilders -- List all domains and verify they are integrated with Sitejet. This function can be domain specific when given an optional domain argument.

    ARGUMENTS
        domain (string) -- Domain name of the website (Optional)

    RETURNS
        Reference to hash of anonymous hashes containing information about
        each domain website which looks something like this:
        $sites = {
            "domain.tld" : {
                "has_sitejet_published"  : 1,
                "has_sitejet_templateId" : 1,
                "is_sitejet"             : 1,
                "has_sitejet_templateId" : 1
            } ...
        };

    ERRORS
        Fatal if cannot load each Sitejet metadata.
        Fatal if cannot get list of domains.
        Fatal if cannot get document roots for current cPanel user.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $sites = $conn_obj->cp_list_all_domain_sitebuilders();

=back

=cut

sub cp_list_all_domain_sitebuilders ( $self, $domain = '' ) {
    my %domain_sitebuilders;

    require Cpanel::DomainLookup::DocRoot;
    my %document_root = %{ Cpanel::DomainLookup::DocRoot::getdocroots($Cpanel::user) };
    my @domains       = $domain ? $domain : keys %document_root;
    foreach my $domain ( sort @domains ) {
        my ( $domain_metadata, $data );
        my $domain_file = "$self->{config_dir}/$domain";
        if ( -e $domain_file ) {
            my $sitejet_metadata = $self->cp_load_sitejet_metadata($domain);
            my $lang             = defined $sitejet_metadata->{'multi_language'} ? ( split /,/, $sitejet_metadata->{'multi_language'} )[0] : '';
            my $index_html       = $lang                                         ? "$document_root{$domain}/$lang/index.html"              : "$document_root{$domain}/index.html";
            $data->{'has_sitejet_templateId'} = exists $sitejet_metadata->{'templateId'}     ? 1 : 0;
            $data->{'has_sitejet_published'}  = exists $sitejet_metadata->{'publish_status'} ? 1 : 0;
            $data->{'has_sitejet_website'}    = exists $sitejet_metadata->{'websiteId'}      ? 1 : 0;
            $data->{'is_sitejet'}             = $self->_read_sitejet_index_html($index_html);
        }
        else {
            $data->{'has_sitejet_templateId'} = 0;
            $data->{'has_sitejet_published'}  = 0;
            $data->{'has_sitejet_website'}    = 0;
            $data->{'is_sitejet'}             = 0;
        }
        $domain_sitebuilders{$domain} = $data;
    }
    return \%domain_sitebuilders;
}

sub _read_sitejet_index_html {
    my ( $self, $index_html ) = @_;

    return 0 if !-e $index_html;
    my $flag = 0;
    open( my $fh, '<', $index_html ) or die Cpanel::Exception::create( "IO::FileOpenError", [ path => $index_html, error => $! ] );

    # plesk looks for this class to identify sitejet
    my $regex = qr{"ed-element};

    while ( my $content = <$fh> ) {
        if ( $content =~ /$regex/ ) {
            $flag = 1;
            last;
        }
    }
    close $fh;

    return $flag;
}

=over

=item * cp_read_json -- Read JSON file or HTTP::Response JSON content and return hash

    ARGUMENTS
        data -- which is either a:
            filename (string) -- Path to file containing JSON.
                or
            dataref -- HTTP::Response object with _content field containing JSON.

    RETURNS
        Reference to hash equivalent to the JSON when the argument is a dataref.
        Hash when the argument is a file name.

    ERRORS
        Fatal if data is not a filename string or HTTP::Response object.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my $hash_ref = $conn_obj->cp_read_json($data);
        my $site_inf = $conn_obj->cp_read_json('/home/batman/sitejet/batman.com');
        my $some_inf = $conn_obj->cp_read_json($response);

=back

=cut

sub cp_read_json {
    my ( $self, $file_or_dataref ) = @_;

    if ( ref $file_or_dataref ) {
        return Cpanel::JSON::Load( $file_or_dataref->{_content} );
    }
    else {
        return %{ Cpanel::JSON::LoadFile($file_or_dataref) };
    }

}

=over

=item * cp_write_json -- Write JSON format file

    Converts contents of a hash to JSON and writes to file.  Overwrites any
    existing content in the file.

    ARGUMENTS
        filename (string) -- Path of file to be written.
        $data (hash ref) -- hash to be converted to JSON.

    RETURNS
        1

    ERRORS
        Fatal if cannot write to file.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        my %hash = ( fullcms => 1, domain => 'batman.com', templateId => '150563' );
        my $result = $conn_obj->cp_write_json( '/home/batman/sitejet/batman.com', \%hash );

=back

=cut

sub cp_write_json {
    my ( $self, $file_name, $data ) = @_;
    require Cpanel::FileUtils::Write;
    Cpanel::FileUtils::Write::overwrite( $file_name, Cpanel::JSON::Dump($data), 0600 );
    return 1;
}

=head1 METHODS

=over

=item * cp_update_logo -- Update cPanel custom logo in Sitejet CMS.

    Update the default cPanel Sitejet Builder logos in sitejet CMS during the
    SSO login. This is an one time update. We store the updated theme as `blob`
    in our default sitejet metadata file.

    ARGUMENTS
        domain (string) -- The website's domain.

    RETURNS:  1 for success.

    ERRORS
        All failures are fatal.

    Note:  This is called during getSSOLinkForWebsite to update logo and the failures are supressed
        as we do not want the whole Sitejet integration to fail. The failures are updated in logs.

    EXAMPLE
        my $result = Cpanel::Sitejet::Connector->cp_update_logo($domain);

=back

=cut

sub cp_update_logo {
    my ( $self, $domain ) = @_;
    my $json_data       = $self->cp_load_sitejet_metadata($domain);
    my $imageType       = 'data:image/svg+xml;base64,';
    my $requires_update = 0;

    # get default theme
    my $light_bg_blob = _get_default_cPanel_blob(DEFAULT_LIGHT_SVG);
    my $dark_bg_blob  = _get_default_cPanel_blob(DEFAULT_DARK_SVG);

    $light_bg_blob = $imageType . $light_bg_blob if length $light_bg_blob;
    $dark_bg_blob  = $imageType . $dark_bg_blob  if length $dark_bg_blob;

    # TODO: DUCK-9037 get customized theme from WHM
    # Some of the below code is designed for the future logic
    if ( $json_data->{'zz_light_bg'} || $json_data->{'zz_dark_bg'} ) {
        if ( $light_bg_blob ne $json_data->{'zz_light_bg'} || $dark_bg_blob ne $json_data->{'zz_dark_bg'} ) {
            $requires_update++;
        }
    }
    else {
        $requires_update++ if ( $light_bg_blob || $dark_bg_blob );
    }
    my $ret;
    if ($requires_update) {
        my $api_token = $self->loadApiKey();
        $self->{'logger'}->info("Updating logo in Sitejet CMS for the domain: '$domain'.");
        $ret = $self->request( 'post', '/account', $api_token, { 'LogoLight' => $light_bg_blob, 'LogoDark' => $dark_bg_blob } );

        # keys have zz prefix to ensure it shows up last when we
        # view the sitejet json file for better readability.
        my $data = {
            'zz_dark_bg'  => $ret->{'partner'}{'editorLogoDark'}  || '',
            'zz_light_bg' => $ret->{'partner'}{'editorLogoLight'} || ''
        };
        $self->cp_update_sitejet_metadata( $domain, $data );
    }
    else {
        $self->{'logger'}->info("Nothing to update. Sitejet CMS has the updated logo for the domain: '$domain'.");
    }

    return 1;
}

sub _get_default_cPanel_blob {
    my $svg = shift;
    my $blob;

    # Cpanel::SafeFile fails due to permission issue while creating a lock
    if ( open( my $fh, '<', $svg ) ) {
        my @data     = <$fh>;
        my $svg_data = join( "", @data );
        require MIME::Base64;
        $blob = MIME::Base64::encode_base64( $svg_data, '' );
        close $fh;
    }
    else {
        die "unable to open file '$svg': $!";
    }
    return $blob;

}

sub execute_list_domains {
    require Cpanel::API;
    my $api_result = Cpanel::API::execute_or_die( 'DomainInfo', 'list_domains', {} );
    return $api_result->data();
}

sub installApiProxy ( $self, $domain, $document_root ) {
    my $user        = $Cpanel::user;
    my $email       = "$user\@$domain";
    my $source_file = API_PHP_TMPL;
    my $target_file = "$document_root/api.php";

    # read API_PHP_TMPL file
    open my $fh, '<', API_PHP_TMPL or Cpanel::Exception::create( "IO::FileOpenError", [ path => $source_file, error => $! ] );
    my @data    = <$fh>;
    my $content = join( "", @data );
    $content =~ s/__API_HOST__/API_HOST/ge;
    $content =~ s/__CLIENT_EMAIL__/$email/g;
    close $fh;

    # write api.php
    open my $write_fh, '>', $target_file or Cpanel::Exception::create( "IO::FileWriteError", [ path => $source_file, error => $! ] );
    print $write_fh $content;
    close $write_fh;
    $file_tracking{$target_file}++;
    return;

}

sub installFlags ( $self, $document_root ) {

    # Clear out old flag copies including Apple artifacts just in case.
    unlink "$document_root/._bundles"                                  if -e "$document_root/._bundles";
    File::Path::remove_tree( "$document_root/bundles", { safe => 1 } ) if -e "$document_root/bundles";

    require Cpanel::Tar;
    require Cpanel::SafeRun::Errors;
    my $tarcfg = Cpanel::Tar::load_tarcfg();
    Cpanel::SafeRun::Errors::saferunallerrors( $tarcfg->{'bin'}, '-C', $document_root, '-v', '-x', '-f', FLAGS_ZIP );

    my @country_flag_files = grep { !m{/$} } map { "$document_root/$_" } Cpanel::SafeRun::Errors::saferunallerrors( $tarcfg->{'bin'}, '-z', '-f', FLAGS_ZIP, '--list' );
    @file_tracking{@country_flag_files} = (1) x @country_flag_files;
    return;
}

sub installLanguages ( $self, $document_root, @languages ) {
    my $file = "$document_root/index.html";
    open my $write_fh, '>', $file or Cpanel::Exception::create( "IO::FileWriteError", [ path => $file, error => $! ] );

    # js expects the languages in an array
    my $js_array = "['" . join( "','", @languages ) . "']";
    my $content  = sprintf( "<script>var a=%s;window.location.href='/'+(navigator.languages.find(l=>a.includes((l||'').toLowerCase().substring(0,2)))||a[0]).substring(0,2);</script>", $js_array );
    print $write_fh $content;
    close $write_fh;

    $file_tracking{$file}++;

    return;
}

sub _check_domain_config {

    # This is only needed for the race condition when a Sitejet plugin update
    # happens and the post-install scriptlet has not moved this cPuser's
    # Sitejet domain configuration file(s) yet.  This check will move over the
    # config files so everything works and we don't have to lock out cPusers
    # because we're doing an update.  Not worried too much about the
    # post-install scriptlet at the same time or later.

    # If no ~/sitejet then return and we're good.
    return if !-e "$Cpanel::homedir/sitejet";

    if ( !-e "$Cpanel::homedir/.cpanel" ) {
        Cpanel::SafeDir::MK::safemkdir_or_die( "$Cpanel::homedir/.cpanel", 0700 );
    }

    my $source_dir      = "$Cpanel::homedir/sitejet";
    my $destination_dir = "$Cpanel::homedir/.cpanel/sitejet";

    if ( !-e $destination_dir ) {
        Cpanel::SafeDir::MK::safemkdir_or_die( "$destination_dir", 0700 );
    }

    my @domains = keys %{ Cpanel::DomainLookup::DocRoot::getdocroots($Cpanel::user) };

    $destination_dir = "$Cpanel::homedir/.cpanel/sitejet";

    foreach my $domain (@domains) {
        if ( -e "$Cpanel::homedir/sitejet/$domain" && is_likely_domain_config( "$Cpanel::homedir/sitejet/$domain", $domain ) ) {
            if ( !rename "$Cpanel::homedir/sitejet/$domain", "$destination_dir/$domain" ) {
                Cpanel::Exception::create( "IO::FileWriteError", [ path => "$destination_dir/$domain", error => "Cannot move '$Cpanel::homedir/sitejet/$domain' to '$destination_dir/$domain' because $!" ] );
                next;
            }
            chmod 0600, "$destination_dir/$domain";
        }
    }

    rm_old_sitejet_dir($Cpanel::homedir);
}

=head1 METHODS

=over

=item * rm_old_sitejet_dir -- If ~/sitejet is empty remove it.

    Called after cleaning out the original Sitejet domain configuration at ~/sitejet.  If the user hasn't put any files in ~/sitejet then we should be able to get rid of it now.

    ARGUMENTS
        home (string) -- cPuser's home directory.

    RETURNS:  undef whether it worked or not.

    ERRORS
        If ~/sitejet cannot be opened to get a list of files.

    EXAMPLE
        Cpanel::Sitejet::Connector->rm_old_sitejet_dir($home);

=back

=cut

sub rm_old_sitejet_dir {

    my $home = shift;

    # One user used ~/sitejet as their document root so we can't
    # just move the entire directory or nuke it if it still has
    # files in it.
    opendir DH, "$home/sitejet" or warn Cpanel::Exception::create( 'IO::DirectoryOpenError', [ path => "$home/sitejet", error => $! ] ) and return;
    my $directory_empty = 1;    # Hoping
    while ( my $file = readdir DH ) {
        next if $file =~ /^\.\.?$/;
        $directory_empty = 0;    # Dang
        last;
    }
    closedir DH;

    if ($directory_empty) {
        rmdir "$home/sitejet";
    }
}

=head1 METHODS

=over

=item * is_likely_domain_config -- Check file to see if might be Sitejet domain configuration file.

    A Sitejet domain configuration file is a JSON format file with specific fields and values.  This checks for what is reasonable and fails on anything that doesn't look right.

    ARGUMENTS
        file (string) -- Filename under question.
        domain (string) -- The website's domain.

    RETURNS:  1 for a possible domain config file.
              0 for a file that is definitely not a domain config file.

    ERRORS
        None.

    EXAMPLE
        my $is_config = Cpanel::Sitejet::Connector->is_likely_domain_config( $file, $domain );

=back

=cut

sub is_likely_domain_config {
    my ( $file, $domain ) = @_;

    return 0 if !-e $file || -z $file || !-f $file;    # Definitely not a domain config file.

    my $contents = eval { Cpanel::JSON::LoadFile($file); };
    return 0 if $@;                                    # Must not have been JSON.

    return 1
      if exists $contents->{cpanelDomainGUID}
      && exists $contents->{document_root}
      && exists $contents->{domain}
      && $contents->{domain} eq $domain
      && exists $contents->{websiteId}
      && $contents->{websiteId} =~ /^\d+$/;
    return 0;
}

=head1 METHODS

=over

=item * cp_save_tracking -- Record full paths of all files downloaded as part of the latest publish().

    Record the full pathname of each file downloaded as part of the current
    publish() action in ~/.cpanel/sitejet/<domain>_files.  This is needed so a
    publish() can recognize and remove old files that are obsolete.

    ARGUMENTS
        domain (string) -- The website's domain.

    RETURNS:  undef in all cases.

    ERRORS
        None.

    EXAMPLE
        my $conn_obj = new Cpanel::Sitejet::Connector;
        $conn_obj->cp_save_tracking($domain);

=back

=cut

sub cp_save_tracking {
    my ( $self, $domain ) = @_;

    my $umask         = Umask::Local->new(077);
    my $tracking_file = "$self->{config_dir}/$domain-files_new";    # Previous file tracking should be in $domain-files
    open my $fh, ">", $tracking_file or Cpanel::Exception::create( "IO::FileWriteError", [ path => $tracking_file, error => $! ] );
    print $fh join( "\n", sort keys %file_tracking ), "\n";
    close $fh;
}

1;
