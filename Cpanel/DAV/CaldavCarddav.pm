#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

package Cpanel::DAV::CaldavCarddav;

use cPstrict;

use Cpanel::SafeDir::RM ();
use IO::Socket;     ##no critic(PreferredModules)
use XML::LibXML;    ##no critic(PreferredModules)
use HTTP::Date qw/time2isoz time2str/;
use HTTP::Headers;
use URI::Escape;    ##no critic(PreferredModules)
use Encode;
use URI;
use File::Find::Rule;
use Cwd;
use Time::HiRes qw ( sleep time );
use MIME::Base64;
use Text::VCardFast;

#use Text::vFile::asData;

# Some helpful URLs to keep readily available:
# https://devguide.calconnect.org/CalDAV/Bootstrapping
# https://wiki.wocommunity.org/display/~probert/CalDAV+and+CardDAV+properties

use Cpanel::DAV::Principal;
use Cpanel::DAV::Defaults;
use Cpanel::DAV::Backend::CPDAVDCalendar;
use Cpanel::DAV::Backend::CPDAVDAddressBook;
use Cpanel::DAV::Metadata ();
use Cpanel::DAV::Logger   qw{iolog logfunc dbg};
use Cpanel::Mkdir         ();
use Cpanel::PwCache;
use Cpanel::Encoder::URI;
use Cpanel::AcctUtils::DomainOwner::Tiny;
use Cpanel::Validate::EmailRFC;

=head1 NAME

Cpanel::DAV::CaldavCarddav - Main implementation of cpdavd's CalDAV and CardDAV support

=cut

my %prefixes              = ( 'DAV:' => 'D', 'http://apple.com/ns/ical/' => 'A', 'urn:ietf:params:xml:ns:caldav' => 'C', 'urn:ietf:params:xml:ns:carddav' => 'CR', 'http://calendarserver.org/ns/' => 'CS' );
my %prefixes_by_long_name = reverse %prefixes;

# Set a product ID for use when generating our own vcard data
my $prodid = '-//WebPros//cPDAVD v1.0//EN';

# Load our lookup table for all property processing
my $lt = _load_properties_lookup_table();

#####################################################################################################################################################################

=head1 CONSTRUCTOR

=head2 new(%opts)

In %opts, you may specify:

=over

=item * auth_user_caldav_root - The base path for the authenticated user's CalDAV and CardDAV files. Typically /home/<cpuser>/.caldav/<authuser>

=item * acct_homedir - The home directory of the account's owner. Typically /home/<cpuser>

=item * sys_user - The cPanel account that owns the authenticated user

=item * auth_user - The authenticated user. May be an email account or the cPanel account.

=item * username - ?

=back

=cut

sub new {
    my ( $class, %args ) = @_;
    my $self = {};
    %{$self} = %args;

    # Uncomment if you want caller backtrace
    #dbg("([new]) : Starting caller() backtrace");
    #for my $i ( 0 .. 30 ) {
    #    my $num = my @caller = caller($i);
    #    if ( $num < 1 ) {
    #        dbg("Caller backtrace complete.");
    #        last;
    #    }
    #    dbg( "Caller($i): ", \@caller );
    #}

    if ( !defined( $self->{'sys_user'} ) ) {    # Required
        dbg("([new]) : mm, no account username given?");
        my @caller = caller();
        die "No sys_user provided @caller";
    }
    if ( !defined( $self->{'acct_homedir'} ) ) {    # Required
        dbg("([new]) : mm, no account homedir given?");
        die "No acct_homedir provided";
    }
    if ( !defined( $self->{'auth_user'} ) ) {       # Optional for functions related to cpanel system user, required if handling DAV calls. This is usually an email address for DAV calls
        dbg("mm, no authenticated given?");
        $self->{'auth_user'} = $self->{'sys_user'};
    }

    $self->{'auth_user_caldav_root'} = $self->{'acct_homedir'} . '/.caldav/' . $self->{'auth_user'} . '/';

    $self->{'metadata'} = Cpanel::DAV::Metadata->new(
        'homedir' => $self->{'acct_homedir'},
        'user'    => $self->{'auth_user'},
    );

    # This is the soonest we can determine a path for log files when called from outside of cpdavd
    # Here we check for the debug flag being set, if it is, maybe_set_debug returns 1 and enables debug logging.
    # If it returns 0, we redefine the dbg function to be a noop. nytprof has shown this saves a considerable percentage of time
    # during calls that loop and hit dbg() thousands of times, and in more extreme cases, millions of times.
    # We do the same for iolog and logfunc as well.
    unless ( Cpanel::DAV::Logger::maybe_set_debug( $self->{'acct_homedir'} ) ) {
        no warnings 'redefine';
        *dbg     = sub { };
        *iolog   = sub { };
        *logfunc = sub { };
    }

    bless $self, $class;
    my @caller = caller();
    dbg("([new]) : looking for $self->{'auth_user_caldav_root'}");

    # Generate default calendar and addressbook if not already present
    if ( !-d $self->{'auth_user_caldav_root'} && $caller[0] ne 'MigrScr' ) {

        # We end up in a cyclical loop of trying to create ourselves if we come from here
        # There is also no need to create the defaults when we are migrating a users data in via the migration script
        dbg("!! $self->{'auth_user_caldav_root'} is not a directory and $caller[0] is not MigrScr !!");

        # Make sure we are running as the user and add /ulc to the local @INC, so localization can be used in the functions in the following block
        my $privs_obj = _drop_privs_if_needed( $self->{'sys_user'} );

        if ( is_over_quota( $self->{'sys_user'} ) ) {
            dbg("([new]) : Account $self->{'sys_user'} is over quota!");    # Considering the nature of this error, this might not get written..
            die "Account $self->{'sys_user'} is over quota!\n";
        }

        push( local @INC, '/usr/local/cpanel' );

        dbg("([new]) : No root $self->{'auth_user_caldav_root'} exists, setting up initial collections");

        # Technically /home/ should be 0755, but if it *does not exist*,
        # then we have bigger problems.
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $self->{'auth_user_caldav_root'}, 0711 );

        my $principal = Cpanel::DAV::Principal::resolve_principal( $self->{'auth_user'} );
        dbg( "([new]) : principal is ", $principal );

        eval {
            my $resp1 = Cpanel::DAV::Defaults::create_calendar($principal);
            dbg( "([new]) :resp1:", $resp1 );
            if ( !$resp1->{'meta'}->{'ok'} ) {
                dbg( "([new]) : Failed to create default calendar", $resp1 );
            }
        };
        if ($@) {
            dbg("([new]) : call to Cpanel::DAV::Defaults::create_calendar( $principal ) failed: $@");
        }
        eval {
            my $resp2 = Cpanel::DAV::Defaults::create_addressbook($principal);
            dbg( "([new]) :resp2:", $resp2 );
            if ( !$resp2->{'meta'}->{'ok'} ) {
                dbg( "([new]) : Failed to create default calendar", $resp2 );
            }
        };
        if ($@) {
            dbg("([new]) : call to Cpanel::DAV::Defaults::create_addressbook( $principal ) failed: $@");
        }
    }

    return $self;
}

############################################################################################
# our various tags
############################################################################################
# dir              - any actual directory
# file             - any actual file, such as vcards, attachments, cat memes
# vcard            - only vcards, like event .ics or .vcf files
# principal        - any request targetting a specific /principals/$principal_user/
# virtprincipals   - specific request to /principals/
# virtcalendars    - specific request to /calendars/
# virtaddressbooks - specific request to /addressbooks/
# allprop          - should be included in an allprop request if the request is relevant (HB-7217 - medium - we are currently handling this in a different place and need to rethink it. we have not yet found a client that required this, however.)
# collection       - any collection, regardless of vcalendar, vaddressbook, vjournal, etc
# vcalendar        - limited to just calendar collections
# vaddressbook     - limited to just addressbook collections
# vjournal         - limited to just journal collections
############################################################################################

# Some definitions : $request_info{'fs_root'}          = file system path to the requested URI/URL/resource, i.e. /home/sysuser/.caldav/principaluser@domain.tld/calendar/f3f3f454f43f43f.ics
#                    $self->{'auth_user_caldav_root'}  = file system path to the authenticated user's base caldav path, i.e. /home/sysuser/.caldav/authuser@domain.tld
# This function records as much as it can about the URI path in the request itself (not generated paths or hrefs in the XML payload)
# It needs to be given at least a path ($request) in the form of either an HTTP::Request object or a relative or full filesystem path. If there is no $response object given, it will try to
# use the one that should be in $self.
sub _parse_request_path {    ##no critic(Subroutines::ProhibitExcessComplexity)
    my ( $self, $request, $response, $original_query_string ) = @_;
    logfunc();

    # Return the cache if we've previously processed it during the lifespan of this request. We only process the HTTP::Request once, currently, but it works here as well.
    $request ||= '';         # Request will be undef in UAPI context

    my %request_info;
    my $path_to_parse;

    # In case _parse_request_path is called with just a path
    if ( !$response && defined $self->{'response_obj'} ) {
        $response = $self->{'response_obj'};
    }
    if ( !$response ) {
        dbg("([_parse_request_path]) : ![Somehow called without a \$response object and \$self did not have one]!");
        $self->{'response_obj'} = $response = HTTP::Response->new();
    }

    # !!! IMPORTANT !!!
    # if $request is not an 'HTTP::Request' object, we assume this is not the initial request, and we just want to parse a path. this means the $self->{'request_info'} should already be populated
    # with details of the initial request. It also means we can assume $response and $original_query_string will be undef and $request will be a scalar with the path to parse

    my $request_ref = ref $request;
    if ( $request_ref eq 'HTTP::Request' ) {
        dbg("([_parse_request_path]) : ref of request is $request_ref");

        $request_info{'uri_raw'} = $request->uri->path;
        $request_info{'method'}  = $request->method();
        $request_info{'depth'}   = $request->header('Depth')                            || 0;
        $self->{'request_ua'}    = $request_info{'ua'} = $request->header('User-Agent') || 'N/A';

        # The server base for cpdavd strips off the ?query=string args long before we arrive at at our entry point in this module, $self->handle().
        # Since that information is often vital (i.e. attachments) , we append the original query string back here
        if ($original_query_string) {
            $request_info{'original_query_string'} = $original_query_string;
            $request_info{'uri_with_query_raw'}    = $request_info{'uri_raw'} . '?' . $original_query_string;
        }

        # Take some effort to normalize and santize our input. While this is all behind an authentication layer, we still want to be mindful of it
        $request_info{'uri_decoded'}      = decode_utf8( URI::Escape::uri_unescape( $request_info{'uri_raw'} ) );
        $request_info{'uri_decoded_safe'} = $self->_safepath( $request_info{'uri_decoded'} );

        # Assign the default file system root for this request, normally 'auth_user_caldav_root' is a path like /home/$sysuser/.caldav/$authenticated-user/
        $request_info{'fs_root'} = $self->{'auth_user_caldav_root'};

        $path_to_parse = $request_info{'uri_decoded_safe'};
    }
    else {
        $path_to_parse = $request;
        $request_info{'req_path'} = $request;    # Saving this here allows us to save the full path even when overwriting 'current_path_info'
    }

    # Previously caching was done using the $request hash itself, however it was discovered that collisions in the hash were not too uncommon (often seen under 1000 tries).
    # Now we cache keying on the path instead.
    dbg("([_parse_request_path]) : PARSING THE FOLLOWING PATH: ([$path_to_parse])");
    if ( defined( $self->{'path_cache'}{$path_to_parse} ) ) {
        dbg( "([_parse_request_path]) : cache hit on ([$path_to_parse]) from ", $request );
        return $self->{'path_cache'}{$path_to_parse};
    }

    if ( $path_to_parse =~ m/^\/(principals|calendars|addressbooks)\/{0,1}$/ ) {
        my $realm = $1;
        dbg("([_parse_request_path]) : This appears to be a direct path request for /$realm/");
        $request_info{'realm'}                      = $realm;
        $request_info{'is_special_virtual_request'} = 1;
        if ( $realm eq 'principals' ) {
            $request_info{'tags'}{'virtprincipals'} = 1;
        }
        elsif ( $realm eq 'calendars' ) {
            $request_info{'tags'}{'virtcalendars'} = 1;
        }
        elsif ( $realm eq 'addressbooks' ) {
            $request_info{'tags'}{'virtaddressbooks'} = 1;
        }

        # Set the principal_user based on the authenticated user since this is a request made for themselves
        $request_info{'principal_user'} = $self->{'auth_user'};

        # Note - This sort of virtual path does not equate to a path on disk, per se. /calendars/ would relate to all vcalendar collections in
        # /home/$sys_user/.caldav/$auth_user/ , same idea applies to /addressbooks/ .
        # BUT, /principals/ is more about principal users in /home/$sys_user/.caldav/

    }
    elsif ( $path_to_parse =~ m/^\/(principals|calendars|addressbooks)\/([^\/]+)(\/.*)?/ ) {

        # Parse and handle virtual URLs, such as the principal user path switcheroo
        my $realm            = $1;
        my $principal_user   = $2;
        my $rest_of_req_path = $3 // '';

        # Make sure %40 is converted back to @ for our purposes
        $principal_user = URI::Escape::uri_unescape($principal_user);

        dbg("([_parse_request_path]) : this req is for a relative/virtual(?) path, realm=$realm , principal user=$principal_user, and rest of request path is ([$rest_of_req_path])");

        if ( $rest_of_req_path =~ m/^\/?\.+/ ) {
            $request_info{'is_special_virtual_request'} = 1;
        }
        else {    # If this was just to /whatever/principal/, tag it as a principal collection ?
            $request_info{'tags'}{'principal'} = 1;
        }

        if ( $rest_of_req_path =~ m/^\/?\.outbox\/?$/ ) {
            dbg("([_parse_request_path]) : tagging as outbox");
            $request_info{'tags'}{'schedule-outbox'} = 1;
            $request_info{'tags'}{'collection'}      = 1;
        }
        elsif ( $rest_of_req_path =~ m/^\/?\.inbox\/?$/ ) {
            dbg("([_parse_request_path]) : tagging as inbox");
            $request_info{'tags'}{'schedule-inbox'} = 1;
            $request_info{'tags'}{'collection'}     = 1;
        }
        elsif ( $rest_of_req_path =~ m/^\/?\.freebusy\/?$/ ) {
            dbg("([_parse_request_path]) : tagging as freebusy");
            $request_info{'tags'}{'freebusy'} = 1;
        }
        elsif ( $rest_of_req_path =~ m/^\/?(calendar-proxy-read|calendar-proxy-write)\/?$/ ) {
            dbg("([_parse_request_path]) : tagging as calendar-proxy-read/write");
            $request_info{'tags'}{'calendar-proxy'} = $1;
        }

        # If the principal_user from the request is different than the authenticated user, get system account owner for $principal_user and
        # rebuild self root to /home/$acct_owner/.caldav/$principal_user
        if ( $principal_user ne $self->{'auth_user'} ) {
            dbg("([_parse_request_path]) : requested resource is not owned by the authenticated user, building request_info data");
            my ( $local, $domain ) = split( /\@/, $principal_user, 2 );
            my $system_owner;
            my $system_owner_homedir;
            if ($domain) {
                $system_owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain);
                if ( $system_owner eq 'root' ) {

                    # The default behavior of Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner() is to return "root" if it can't find a better owner.
                    # There is no situation where we have an authenticated email address user logging in to a domain not owned by a regular account, so this
                    # is a show stopper.
                    dbg("([_parse_request_path]) : Unknown domain given in principal ($principal_user), returning hard error");
                    $response->code(400);
                    $response->message('Invalid principal user');
                    goto QUICKEXIT;
                }
                if ( $self->{'sys_user'} ne $system_owner ) {
                    dbg("([_parse_request_path]) : Authenticated user ($self->{'sys_user'}) attempting to access server for principal ($principal_user) on a different account ($system_owner), returning hard error");
                    $response->code(403);
                    $response->message('Invalid principal user');
                    goto QUICKEXIT;
                }
                $system_owner_homedir = scalar( ( Cpanel::PwCache::getpwnam($system_owner) )[7] );
                dbg("([_parse_request_path]) : owner of $domain is $system_owner , home path is $system_owner_homedir");
            }
            else {
                dbg("([_parse_request_path]) : $principal_user is not a virtual mail user account");
                if ( $self->{'sys_user'} ne $principal_user ) {
                    dbg( "([_parse_request_path]) : Authenticated user ($self->{'sys_user'}) attempting to access server for a different account ($principal_user), returning hard error", $response );
                    $response->code(403);
                    $response->message('Invalid principal user');
                    goto QUICKEXIT;
                }
                $system_owner         = $principal_user;
                $system_owner_homedir = scalar( ( Cpanel::PwCache::getpwnam($principal_user) )[7] );
                dbg("([_parse_request_path]) : in that case, $system_owner_homedir is the base path");
            }
            my $actual_request_path = $system_owner_homedir . '/.caldav/' . $principal_user;
            $request_info{'system_account'}         = $system_owner;
            $request_info{'system_account_homedir'} = $system_owner_homedir;
            $request_info{'fs_root'}                = $system_owner_homedir . '/.caldav/' . $principal_user;
            $request_info{'fs_root'} =~ s/\/\/+/\//g;

            # check that the directory for the user exists, otherwise it's probably an invalid user. We can check the fs_root for this since we haven't re-appended the rest of the request yet.
            if ( !-d $request_info{'fs_root'} ) {
                dbg("([_parse_request_path]) : Authenticated user ($self->{'sys_user'}) attempting to access server for principal ($principal_user) which does not exist at ([$request_info{'fs_root'}]), returning hard error");
                $response->code(403);
                $response->message('Invalid principal user');
                goto QUICKEXIT;
            }
        }

        if ( !defined $request_info{'fs_root'} ) {
            dbg("([_parse_request_path]) : No fs_root at this point, generating the default from ([$self->{'auth_user_caldav_root'}])");
            $request_info{'fs_root'} = $self->{'auth_user_caldav_root'};
        }

        # Set the freebusy file path based on the authenticated user. This should work for organizers as well as people accepting/declining invites
        $request_info{'fb_file_path'} = $self->{'acct_homedir'} . '/.caldav/' . $self->{'auth_user'} . '/.freebusy.json';

        $request_info{'fs_base_principal_path'} = $request_info{'fs_root'};
        $request_info{'fs_root'}                = $request_info{'fs_root'} . '/' . $rest_of_req_path;
        $request_info{'fs_root'} =~ s/\/\/+/\//g;

        if ( $realm eq 'principals' ) {
            $request_info{'tags'}{'principal'}  = 1;
            $request_info{'tags'}{'collection'} = 1;
        }

        # $rest_of_req_path in this context is what is after "/calendars|principals|addressbooks/user@dom.tld" , so "", / , /calendarname/ , /calendarname/eventfile.ics , etc.
        if ( length($rest_of_req_path) > 1 ) {    # more than just /
            my (@path_parts) = split( '/', $rest_of_req_path );
            @path_parts = grep { $_ ne '' } @path_parts;

            # dbg("([_parse_request_path]) : path parts HERE : @path_parts");
            $request_info{'collection'} = $path_parts[0];    # set the collection name, mostly useful for creating the x-cpanel-id when sending invites

            # If the request ends at the collection, mark it as such and load metadata to determine what sort of collection
            if ( !$path_parts[1] && $path_parts[0] !~ m/^\./ ) {
                my $existing_metadata_hr = $self->{'metadata'}->load();

                # dbg("([_parse_request_path]) : metadata : ", $existing_metadata_hr );
                if ( defined( $existing_metadata_hr->{ $request_info{'collection'} } ) ) {
                    $request_info{'tags'}{'collection'} = 1;
                    my $collection_type = $existing_metadata_hr->{ $request_info{'collection'} }{'type'};
                    if ( $collection_type eq 'VCALENDAR' ) {
                        $request_info{'tags'}{'vcalendar'} = 1;
                    }
                    elsif ( $collection_type eq 'VADDRESSBOOK' ) {
                        $request_info{'tags'}{'vaddressbook'} = 1;
                    }
                    elsif ( $collection_type eq 'VJOURNAL' ) {
                        $request_info{'tags'}{'vjournal'} = 1;
                    }
                }
                else {
                    dbg("([_parse_request_path]) : Could not find metadata entry for the collection $request_info{'collection'} ?");
                }
            }

            # If we have anything else, it has to be an event vcard file or an attachment, we don't support anything else here right now
            else {
                dbg("([_parse_request_path]) : either we have more url parts passed the collection, or is a restricted special/virtual path");
            }
        }
        else {
            dbg("([_parse_request_path]) : No collection specified in request");
            if ( $realm eq 'principals' ) {
                $request_info{'tags'}{'virtprincipals'} = 1;
            }
            elsif ( $realm eq 'calendars' ) {
                $request_info{'tags'}{'virtcalendars'} = 1;
            }
            elsif ( $realm eq 'addressbooks' ) {
                $request_info{'tags'}{'virtaddressbooks'} = 1;
            }
        }

        dbg("([_parse_request_path]) : fs_root of requested resource ([$path_to_parse]) mapped to ([$request_info{'fs_root'}])");

        $request_info{'realm'}          = $realm;
        $request_info{'principal_user'} = $principal_user;
        $request_info{'metadata_path'}  = $self->{'acct_homedir'} . '/.caldav/' . $principal_user . '/.metadata';

        dbg("([_parse_request_path]) : breaking down rest_of_req_path, ([$rest_of_req_path])");

        $request_info{'special_virtual_subpath'} = $rest_of_req_path;

        if ( $rest_of_req_path eq '/calendar-proxy-write/' or $rest_of_req_path eq '/calendar-proxy-read/' ) {
            dbg("([_parse_request_path]) : This is a special request for querying proxy groups");
            $request_info{'is_special_virtual_request'} = 1;
            return \%request_info;
        }

        # Add other specific path handlers here when the need arises.

    }

    # this function sometimes gets passed in full fs paths, such as /home/cptech1/.caldav/ttt@cptech1.test/funky/7570c191-4a19-48c3-899b-7b59976676c7.ics
    # so we need to detect that for common cases and process it accordingly.
    elsif ( $path_to_parse =~ m/^(\/.+)\/\.caldav\/(.+)$/ ) {

        # We potentially have a full fs path, as /.caldav/ shouldn't show up in http/dav requests to the server as they are all relative paths
        $request_info{'fs_root'} = $path_to_parse;
        my $parsed_home_dir  = $1;
        my $post_caldav_path = $2;
        dbg("([_parse_request_path]) : this looks like it could be a full filesystem path, parsed_home_dir is ([$parsed_home_dir]) , post_caldav_path is ([$post_caldav_path])");

        if ( $post_caldav_path =~ m/\.calendar\-proxy\-read\/?$/ ) {
            dbg("([_parse_request_path]) : tagging as calendar-proxy");
            $request_info{'tags'}{'calendar-proxy'} = 'calendar-proxy-read';
        }
        elsif ( $post_caldav_path =~ m/\.calendar\-proxy\-write\/?$/ ) {
            dbg("([_parse_request_path]) : tagging as calendar-proxy");
            $request_info{'tags'}{'calendar-proxy'} = 'calendar-proxy-write';
        }

        if ( -d $parsed_home_dir ) {

            my ( $user, $collection, $rest ) = split( '/', $post_caldav_path );

            # suppress warnings below when collection is nonexistent due to a path like /principals/user@domain with no additional colection path underneath
            $collection //= '';

            dbg("([_parse_request_path]) : assuming user is $user, collection is $collection");
            dbg("([_parse_request_path]) : the 'rest' is $rest") if length $rest;

            $request_info{'principal_user'} = $user;
            $request_info{'metadata_path'}  = $self->{'acct_homedir'} . '/.caldav/' . $user . '/.metadata';

            if ( $collection =~ m/^\/?\.+/ ) {
                $request_info{'is_special_virtual_request'} = 1;
            }
            if ( $collection =~ m/\.outbox\/?$/ ) {
                dbg("([_parse_request_path]) : tagging as outbox");
                $request_info{'tags'}{'schedule-outbox'} = 1;
                $request_info{'tags'}{'collection'}      = 1;
            }
            elsif ( $collection =~ m/\.inbox\/?$/ ) {
                dbg("([_parse_request_path]) : tagging as inbox");
                $request_info{'tags'}{'schedule-inbox'} = 1;
                $request_info{'tags'}{'collection'}     = 1;
            }
            elsif ( $collection =~ m/\.freebusy\/?$/ ) {
                dbg("([_parse_request_path]) : tagging as freebusy");
                $request_info{'tags'}{'freebusy'} = 1;
            }

            # If this is a special virtual type, handle it, otherwise treat it like a legit path
            elsif ( $collection =~ m/^(calendars|principals|addressbooks)$/ ) {
                dbg("([_parse_request_path]) : looks like a special virtual request for $collection");
                $request_info{'collection'}         = '';
                $request_info{'realm'}              = $collection;
                $request_info{'principal_user'}     = $user;
                $request_info{'uri_extra_parts_ar'} = $rest || '';
            }
            else {
                if ( !length($collection) && -d $parsed_home_dir . '/.caldav/' . $user . '/' ) {
                    dbg("([_parse_request_path]) : full fs path verified up through collection ([$parsed_home_dir/.caldav/$user])");
                    $request_info{'principal_user'} = $user;
                }
                elsif ( length($collection) && -d $parsed_home_dir . '/.caldav/' . $user . '/' . $collection ) {
                    dbg("([_parse_request_path]) : full fs path verified up through collection $collection");
                    $request_info{'collection'}         = $collection;
                    $request_info{'principal_user'}     = $user;
                    $request_info{'uri_extra_parts_ar'} = $rest || '';

                    # if this request ends at the collection, process it as a collection. If there is more to it, it's probably a file of some sort
                    if ( !length $request_info{'uri_extra_parts_ar'} ) {
                        my $existing_metadata_hr = $self->{'metadata'}->load( $parsed_home_dir . '/.caldav/' . $user . '/.metadata' );
                        dbg( "([_parse_request_path]) : metadata got $collection: ", $existing_metadata_hr );
                        if ( defined( $existing_metadata_hr->{$collection} ) ) {
                            $request_info{'tags'}{'collection'} = 1;
                            my $collection_type = $existing_metadata_hr->{$collection}{'type'};
                            if ( $collection_type eq 'VCALENDAR' ) {
                                $request_info{'tags'}{'vcalendar'} = 1;
                            }
                            elsif ( $collection_type eq 'VADDRESSBOOK' ) {
                                $request_info{'tags'}{'vaddressbook'} = 1;
                            }
                            elsif ( $collection_type eq 'VJOURNAL' ) {
                                $request_info{'tags'}{'vjournal'} = 1;
                            }
                        }
                        else {
                            dbg("([_parse_request_path]) : Could not find metadata entry for the collection $request_info{'collection'} ?");
                        }
                    }
                    else {
                        if ( -f $path_to_parse ) {
                            $request_info{'tags'}{'file'} = 1;
                            if ( $path_to_parse =~ m/\.(ics|vcf)$/i ) {
                                $request_info{'tags'}{'vcard'} = 1;
                            }
                        }
                        elsif ( -d _ ) {
                            $request_info{'tags'}{'dir'} = 1;
                        }
                    }
                }
                else {
                    dbg("([_parse_request_path]) : full fs path ([$parsed_home_dir/.caldav/$user/$collection]) does not appear to be a directory.. ![this will likely cause issues]!.");
                }
            }
        }

        # Look at the request URI and handle as many special cases as we can, parsing it for anything that might be usable later
    }
    else {
        dbg("([_parse_request_path]) : ![Did not match any known/expected URI types, assuming a direct path/file request]!");
        $request_info{'fs_root'} = $self->{'auth_user_caldav_root'} . $self->{'request_info'}{'uri_decoded_safe'};
    }

    # Determine what tags we should apply

    # special virtual requests like /principals/ do not truly map to a filesystem path
    # Don't consider collections or virtual requests to be directories, this should actually be pretty rare as we don't offer up raw directories.
    if (   !$request_info{'is_special_virtual_request'}
        && !$request_info{'collection'}
        && !$request_info{'tags'}{'virtprincipals'}
        && !$request_info{'tags'}{'virtcalendars'}
        && !$request_info{'tags'}{'virtaddressbooks'} ) {
        if ( -d $request_info{'fs_root'} ) {
            dbg("([_parse_request_path]) : FS_ROOT IS A DIR");
            $request_info{'tags'}{'dir'} = 1;
        }
        elsif ( -f _ ) {
            $request_info{'tags'}{'file'} = 1;
            dbg("([_parse_request_path]) : FS_ROOT IS A FILE");

            # If this file looks like a vcard, tag it as such
            if ( $request_info{'fs_root'} =~ m/\.(ics|vcf)$/i ) {
                $request_info{'tags'}{'vcard'} = 1;
                dbg("([_parse_request_path]) : FS_ROOT IS A VCARD");
            }
        }
    }
    if ( exists( $request_info{'fs_root'} ) && $request_info{'fs_root'} =~ m/^(\/.+)\/\.caldav\/(.+)$/ ) {
        dbg("([_parse_request_path]) : we have a full path from ([$path_to_parse]) : ([$request_info{'fs_root'}]) ");

        # A bare / is a special condition, usually as a result of querying /.well-known/(caldav|carddav) and being redirected
        # In this situation, we want to allow a limited set of properties to be queried, so we issue a tag indicating it
        if ( length( $self->{'request_info'}{'uri_raw'} ) && $self->{'request_info'}{'uri_raw'} eq '/' ) {
            $request_info{'tags'}{'discovery'} = 1;
        }
        dbg( "([_parse_request_path]) : returning request_info on this path : ", \%request_info );
    }

    # Cache the result for any hits later
    $self->{'path_cache'}{$path_to_parse} = \%request_info;
    return \%request_info;
}

# remove the root directory from a real filesystem path and return what remains
sub _virtualpath {
    my ( $self, $path ) = @_;
    logfunc();
    return '' if !length $path;
    $path =~ s/\%40/\@/g;
    dbg( "([_virtualpath]) : incoming path is ([$path])", $self );
    if ( $path =~ m/^$self->{'auth_user_caldav_root'}/ ) {    # Note - auth_user_caldav_root already ends in / so we don't need to anchor it
        dbg("([_virtualpath]) : path (([$path])) starts with ([$self->{'auth_user_caldav_root'}])");
        $path = substr( $path, length( $self->{'auth_user_caldav_root'} ) );
        dbg("([_virtualpath]) : path is now (([$path])), but we want no leading or trailing forward slashes.. ?");
        $path =~ s/^\/+//g;
        $path =~ s/\/+$//g;
        dbg("([_virtualpath]) : with /'s removed : (([$path]))");
        return $path;
    }
    else {
        # Handle cases where the path is shared, so it would not start with the authenticated user's caldav base path
        dbg("([_virtualpath]) : ([$path]) does not start with ([$self->{'auth_user_caldav_root'}]) , assuming this is for a shared path");
        my @path_parts = split( '/', $path );
        my @root_parts = split( '/', $self->{'auth_user_caldav_root'} );

        my $min_length = @path_parts < @root_parts ? @path_parts : @root_parts;

        my $seen_caldav = 0;
        my $seen_caldav_index;

        # See if the requested path and the authed user path are based in the same .caldav/ directory
        for my $i ( 0 .. $min_length - 1 ) {
            dbg("([_virtualpath]) : request path $i ([$path_parts[$i]]) vs auth user root ([$root_parts[$i]])");
            if ( $path_parts[$i] ne $root_parts[$i] ) {
                dbg("([_virtualpath]) : paths diverge at $i");
                $seen_caldav_index = $i;
                last;
            }
            else {
                if ( $path_parts[$i] eq '.caldav' ) {
                    dbg("([_virtualpath]) : marking \$seen_caldav = 1");
                    $seen_caldav = 1;
                }
            }
        }

        if ( $seen_caldav == 1 ) {
            dbg( "([_virtualpath]) : path_parts is ", \@path_parts );

            # Get the expected virtual path from the remaining args
            my @leftover_path_parts = grep { defined($_) } @path_parts[ $seen_caldav_index + 1 .. scalar(@path_parts) ];
            dbg( "([_virtualpath]) : leftover_path_parts is ", \@leftover_path_parts );
            if (@leftover_path_parts) {
                my $rest_of_path_after_user = join( '/', @leftover_path_parts );
                $rest_of_path_after_user =~ s/^\///g;
                $rest_of_path_after_user =~ s/\/$//g;
                dbg("([_virtualpath]) : gonna return -[$rest_of_path_after_user]-");
                return $rest_of_path_after_user;
            }
            else {
                return '';
            }
        }
        else {
            dbg("([_virtualpath]) : paths diverged before we found .caldav , something seems very wrong here !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!.");
            return '';
        }
    }
}

# Give the $path in the current context, determine and return what the URL should be for an href
# If this is from a special virtual path, add it back here so clients don't get confused on the URL path. e.g. http://dom.tld:2080/calendars/user@dom.tld/calendar/ but $display_path is just /calendar
sub _get_display_path {    ##no critic(Subroutines::ProhibitExcessComplexity)
    my ( $self, $path ) = @_;
    logfunc();

    my $display_path = '';

    $path =~ s/\%40/\@/;
    my $path_hr = $self->_parse_request_path($path);

    #    dbg( "([_get_display_path]) : path_hr and self : ", $path_hr, $self );
    dbg( "([_get_display_path]) : path_hr :", $path_hr );
    dbg("([_get_display_path]) : incoming path is ([$path])");

    # Check if the path is owned by the authenticated user, which simplifies things. Otherwise, break the path apart and rebuild it for the relevant principal user
    if ( $path =~ m/^$self->{'auth_user_caldav_root'}/ ) {    # Note - auth_user_caldav_root already ends in / so we don't need to anchor it
        dbg("([_get_display_path]) : path (([$path])) starts with ([$self->{'auth_user_caldav_root'}])");
        $path = substr( $path, length( $self->{'auth_user_caldav_root'} ) );
        dbg("([_get_display_path]) : path is now (([$path]))");

        # If this is a virtual .inbox|.outbox|.freebusy request, format it
        if (   $path_hr->{'tags'}{'schedule-inbox'}
            or $path_hr->{'tags'}{'schedule-outbox'}
            or $path_hr->{'tags'}{'freebusy'}
            or ( $path_hr->{'req_path'} && $path_hr->{'req_path'} =~ m/\/calendar-proxy-(read|write)/ ) ) {
            dbg("([_get_display_path]) : this is tagged as a virtual scheduling path");
            $display_path = '/' . $self->{'request_info'}{'realm'} . '/' . $self->{'request_info'}{'principal_user'} . '/' . $path . '/';
        }
        elsif ( length $path_hr->{'principal_user'} && length $path_hr->{'collection'} ) {
            if ( defined $path_hr->{'tags'}{'vcalendar'} ) {
                $display_path = '/calendars/' . $path_hr->{'principal_user'} . '/' . $path_hr->{'collection'} . '/';
            }
            elsif ( defined $path_hr->{'tags'}{'vaddressbook'} ) {
                $display_path = '/addressbooks/' . $path_hr->{'principal_user'} . '/' . $path_hr->{'collection'} . '/';
            }
            elsif ( defined $path_hr->{'tags'}{'vjournal'} ) {
                $display_path = '/calendars/' . $path_hr->{'principal_user'} . '/' . $path_hr->{'collection'} . '/';
            }
            elsif ( defined $path_hr->{'tags'}{'file'} ) {
                if ( length $self->{'request_info'}{'realm'} ) {
                    $display_path = '/' . $self->{'request_info'}{'realm'} . '/' . $path_hr->{'principal_user'} . '/' . $path;
                }
                else {
                    $display_path = '/calendars/' . $path_hr->{'principal_user'} . '/' . $path;
                }
            }
            else {
                dbg("([_get_display_path]) : ![falling back to a default, if you see this it might mean something is wrong/odd, like the path not existing on disk]!");
                if ( length $self->{'request_info'}{'realm'} ) {
                    $display_path = '/' . $self->{'request_info'}{'realm'} . '/' . $path_hr->{'principal_user'} . '/' . $path;
                }
                else {
                    $display_path = '/calendars/' . $path_hr->{'principal_user'} . '/' . $path;
                }
            }
            dbg("([_get_display_path]) : we have principal_user and collection from $path, display_path is currently $display_path");
        }
    }
    else {
        # Handle cases where the path is shared, so it would not start with the authenticated user's caldav base path
        dbg("([_get_display_path]) : ([$path]) does not start with ([$self->{'auth_user_caldav_root'}]) , assuming this is for a shared path");
        my @path_parts = split( '/', $path );
        my @root_parts = split( '/', $self->{'auth_user_caldav_root'} );

        my $min_length = @path_parts < @root_parts ? @path_parts : @root_parts;

        my $seen_caldav = 0;
        my $seen_caldav_index;

        # See if the requested path and the authed user path are based in the same .caldav/ directory
        for my $i ( 0 .. $min_length - 1 ) {
            dbg("([_get_display_path]) : request path $i ([$path_parts[$i]]) vs auth user root ([$root_parts[$i]])");
            if ( $path_parts[$i] ne $root_parts[$i] ) {
                dbg("([_get_display_path]) : paths diverge at $i");
                $seen_caldav_index = $i;
                last;
            }
            else {
                if ( $path_parts[$i] eq '.caldav' ) {
                    dbg("([_get_display_path]) : marking \$seen_caldav = 1");
                    $seen_caldav = 1;
                }
            }
        }

        if ( $seen_caldav == 1 ) {
            dbg( "([_get_display_path]) : path_parts is ", \@path_parts );

            $seen_caldav_index //= 0;    # FIXME: On paths like /principals/<user> without a third part, this remains undefined

            # Get the expected virtual path from the remaining args
            my @leftover_path_parts = grep { defined($_) } @path_parts[ $seen_caldav_index + 1 .. scalar(@path_parts) ];
            dbg( "([_get_display_path]) : leftover_path_parts is ", \@leftover_path_parts );
            my $rest_of_path = join( '/', @leftover_path_parts );

            if ( length $path_hr->{'principal_user'} && length $path_hr->{'tags'}{'collection'} ) {
                if ( defined $path_hr->{'tags'}{'vcalendar'} ) {
                    $display_path = '/calendars/' . $path_hr->{'principal_user'} . '/' . $rest_of_path . '/';
                }
                elsif ( defined $path_hr->{'tags'}{'vaddressbook'} ) {
                    $display_path = '/addressbooks/' . $path_hr->{'principal_user'} . '/' . $rest_of_path . '/';
                }
                elsif ( defined $path_hr->{'tags'}{'vjournal'} ) {    # currently journals are semi-supported as a calendar collection, it uses .ics files as well.
                    $display_path = '/calendars/' . $path_hr->{'principal_user'} . '/' . $rest_of_path . '/';

                    # If this is a virtual .inbox|.outbox|.freebusy request, format it
                }
                elsif ($path_hr->{'tags'}{'schedule-inbox'}
                    or $path_hr->{'tags'}{'schedule-outbox'}
                    or $path_hr->{'tags'}{'freebusy'}
                    or $path_hr->{'req_path'} =~ m/\/calendar-proxy-(read|write)/ ) {
                    dbg("([_get_display_path]) : this is tagged as a virtual scheduling path");
                    $display_path = '/' . $self->{'request_info'}{'realm'} . '/' . $self->{'request_info'}{'principal_user'} . '/' . $rest_of_path . '/';
                }
                else {
                    dbg( "([_get_display_path]) : path not tagged as calendar, addressbook or journal ? ", $path_hr );
                    $display_path = $self->{'request_info'}{'uri_decoded_safe'} . $rest_of_path . '/';
                }
                dbg("([_get_display_path]) : display_path is currently ([$display_path])");
            }    # handle d:0 /principals/user@dom.tld/ > /home/user/.caldav/user@dom.tld/
            elsif ( length $path_hr->{'principal_user'} && !length $path_hr->{'tags'}{'collection'} ) {
                dbg( "([_get_display_path]) : request has a principal user but no collection", $path_hr );
                if ( length $path_hr->{'principal_user'} && length $path_hr->{'tags'}{'calendar-proxy'} ) {
                    dbg("([_get_display_path]) : request includes a calendar-proxy tag");
                    $display_path = '/principals/' . $path_hr->{'principal_user'} . '/' . $path_hr->{'tags'}{'calendar-proxy'};
                }
                elsif ( defined $self->{'request_info'}{'tags'}{'virtprincipals'} && $self->{'request_info'}{'tags'}{'virtprincipals'} == 1 ) {
                    dbg("([_get_display_path]) : request includes virtprincipals tag");
                    $display_path = '/principals/' . $path_hr->{'principal_user'} . '/';
                }
                elsif ( defined $self->{'request_info'}{'tags'}{'virtcalendars'} && $self->{'request_info'}{'tags'}{'virtcalendars'} == 1 ) {
                    dbg("([_get_display_path]) : request includes virtcalendars tag");
                    $display_path = '/calendars/' . $path_hr->{'principal_user'} . '/';
                }
                elsif ( defined $path_hr->{'principal_user'} && !defined $self->{'request_info'}{'realm'} && defined $path_hr->{'tags'}{'discovery'} ) {
                    dbg("([_get_display_path]) : no realm but discovery tag is present");
                    $display_path = '/';
                }
                else {
                    if ( length $self->{'request_info'}{'realm'} ) {
                        if ( length($rest_of_path) ) {
                            $display_path = _strict_concat( '/', $self->{'request_info'}{'realm'}, '/', $path_hr->{'principal_user'}, '/' . $rest_of_path );
                        }
                        else {
                            $display_path = _strict_concat( '/', $self->{'request_info'}{'realm'}, '/', $path_hr->{'principal_user'}, '/' );
                        }
                    }
                    else {
                        dbg("([_get_display_path]) : Ended up at a fallback for setting display path");
                        $display_path = $self->{'request_info'}{'uri_decoded_safe'};
                    }
                }
            }
            if ( defined $path_hr->{'tags'}{'file'} ) {
                if ( length $self->{'request_info'}{'realm'} ) {
                    dbg("([_get_display_path]) : adding \$path ([$path]) to /\$realm/\$principal_user");
                    $display_path = '/' . $self->{'request_info'}{'realm'} . '/' . $path_hr->{'principal_user'} . '/' . $rest_of_path;
                }
                else {
                    # This is a fallback, but if we get here, it's a failure of the parsing
                    dbg("([_get_display_path]) : adding \$rest_of_path ([$rest_of_path]) to /calendars/\$principal_user . ![Hitting this point should not happen.]!");
                    $display_path = '/calendars/' . $path_hr->{'principal_user'} . '/' . $rest_of_path;
                }
            }

        }
        else {
            dbg("([_get_display_path]) : paths diverged before we found .caldav , something seems very wrong here !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!.");
            return '';
        }
    }

    # Never leave this empty
    if ( !$display_path ) {
        dbg("([_get_display_path]) : ![\$display_path was empty, probably want to investigate this]!");
        $display_path = '/';
    }

    $display_path =~ s/\/+/\//g;
    dbg("([_get_display_path]) : returning ([$display_path])");
    return $display_path;
}

####################################################################################################
#######[ This is the initial entry point for handling caldav/carddav requests from cpdavd ]#########
####################################################################################################

=head1 METHODS

=head2 handle($cphttpd, $c, $username, $original_query_string)

The initial entry point for handling CalDAV/CardDAV requests from cpdavd.

Arguments:

=over

=item - $cphttpd - The Cpanel::Httpd object being used for servicing the request.

=item - $c - The socket from which the request body may be read (if applicable) and to which a response may be printed.

=item - $username - The user for which the request is being handled.

=item - $original_query_string - The query string associated with the request, if any.

=back

=cut

sub handle {    ## no critic qw(ProhibitExcessComplexity)
    my ( $self, $cphttpd, $c, $username, $original_query_string ) = @_;
    logfunc();

    $self->{'smtp_user'} = $cphttpd->{'smtp_user'};
    $self->{'smtp_pass'} = $cphttpd->{'smtp_pass'};
    my $request = $cphttpd->{'httprequest'};

    dbg("-[handle]- : original_query_string is $original_query_string") if length($original_query_string);

    $self->{'username'} = $username;

    my $method     = $request->method();
    my $user_agent = $request->header('User-Agent') || 'N/A';
    my $depth      = $request->header('Depth')      || 0;
    my $content    = $request->content();

    dbg("-[handle]- : method = $method") if defined $method;

    # Generate a response object for this request and ensure it's "always" available by stuffing it in $self
    require HTTP::Response;
    my $response = HTTP::Response->new;
    $self->{'response_obj'} = $response;

    # At this early stage, we need to take the request and handle virtual paths, set all variables and refer to those rather than reparsing the path from the request.
    # Doing this lets us keep the logic in one place.
    # Note that the request uri has been stripped of any ?query=string&data=whatever , but we have it available in $original_query_string
    # This will populate $self->{'request_info'} that can be referred to in all sorts of situations. The $request will/should only be processed once.
    my $parsed_initial_request_hr = $self->_parse_request_path( $request, $response, $original_query_string );
    $self->{'request_info'} = $parsed_initial_request_hr;

    dbg( "-[handle]- : self after _parse_request_path : ", $self );

    # We don't call _parse_request_payload this early since not all of these are XML payloads. Instead we call it only in method handler functions that can use it.

    iolog(
        "\n>>>==[ Request ]================================================>>>>\n",
        ">>> $method " . $request->uri->path . "\n",
        ">>> FS ROOT $self->{'request_info'}{'fs_root'}\n",
        ">>> USER_AGENT $user_agent\n",
        ">>> DEPTH $depth\n",
        ">>>==[ Payload ]================================================>>>>\n",
        $content . "\n",
        "<<<==[ End Payload ]============================================>>>>",
    );

    # We should never have a caldav client using directory traversal.
    # This check ultimately relies on URI::Escape::uri_unescape
    if ( $self->{'request_info'}{'uri_decoded'} =~ m/\/\.\.\// ) {
        dbg("-[handle]- : *[$method]* ![Blocking directory traversal]! ([$self->{'request_info'}{'uri_decoded'}])");
        $response->code(403);
        $response->message("Invalid Request");
        goto QUICKEXIT;
    }

    # If the request is a PUT or POST, check various elements of the request to see if we want to block them early.
    # Check that the path includes principals|calendars|addressbooks/princi@palu.ser/collection/ with a file after it.

    if ( $method eq 'PUT' or $method eq 'POST' ) {
        dbg("-[handle]- : Performing security check on request via $method call");
        my $err_code;
        my $err_msg    = "$method request not allowed on path";    # Default for error, can override if really needed based on specific check
        my @path_parts = split( '/', $request->uri->path );
        my $last_part  = pop(@path_parts);
        dbg("-[handle]- : last_part is $last_part");

        # Exempt special virtual paths we expect PUTs or POSTs to.
        my @allowed_exemptions = ( '.inbox', '.outbox', '.freebusy', 'calendar-proxy-read', 'calendar-proxy-write' );
        if ( grep { $_ eq $last_part } @allowed_exemptions ) {
            dbg("-[handle]- : allowing exempted special virtual path ([$last_part])");
        }
        elsif ( substr( $last_part, 0, 1 ) eq '.' ) {
            $err_code = 403;
            dbg("-[handle]- : ![Uploads not allowed to start with a period]! ([$last_part])");
        }
        elsif ( !length $self->{'request_info'}{'collection'} ) {
            $err_code = 403;
            dbg("-[handle]- : ![Uploads not allowed outside a collection]!");
        }
        else {
            # Ensure that the collection is in metadata
            my $type = $self->_get_metadata_property( $self->{'request_info'}{'fs_root'}, 'type' );
            if ( !length $type ) {
                $err_code = 403;
                dbg("-[handle]- : ![Request is for a collection not found in the metadata]!");
            }
            elsif ( $type ne 'VCALENDAR' && $type ne 'VADDRESSBOOK' ) {
                $err_code = 403;
                dbg("-[handle]- : ![Request is to an invalid collection, neither calendar or address book]! -[$type]-");

                # A 'POST' request to a collection dir can be used to grant sharing, so we limit this to PUTs
            }
            elsif ( $method eq 'PUT' && $type eq 'VCALENDAR' && substr( $last_part, -4, 4 ) ne '.ics' ) {
                $err_code = 403;
                dbg("-[handle]- : ![Request is to a valid a calendar collection but file]! ([$last_part]) ![is not a .ics vcard]!");
            }
            elsif ( $type eq 'VADDRESSBOOK' && substr( $last_part, -4, 4 ) ne '.vcf' ) {
                $err_code = 403;
                dbg("-[handle]- : ![Request is to a valid a address book collection but file]! ([$last_part]) ![is not a .vcf vcard]!");
            }
        }

        if ( length $err_code ) {
            dbg("-[handle]- : *[$method]* ![request failed security limitations check]! ($err_code) ($err_msg)");
            $response->code($err_code);
            $response->message($err_msg);
            goto QUICKEXIT;
        }
    }

    # Assume Success (tm). Probably useless but it's funny at least.
    $response->code('200');

    if ( $method eq "OPTIONS" ) {
        $self->_options( $request, $response );
    }
    elsif ( $method eq "PUT" ) {
        $self->_put( $request, $response, $c );
    }
    elsif ( $method eq "GET" ) {
        $self->_get( $request, $response );
    }
    elsif ( $method eq "HEAD" ) {
        $self->_head( $request, $response );
    }
    elsif ( $method eq "DELETE" ) {
        $self->_delete( $request, $response );
    }
    elsif ( $method eq "PROPFIND" ) {
        $self->_request_wrapper( $request, $response );
    }
    elsif ( $method eq "REPORT" ) {
        $self->_request_wrapper( $request, $response );
    }
    elsif ( $method eq "PROPPATCH" ) {
        $self->_proppatch( $request, $response, $c );
    }
    elsif ( $method eq "POST" ) {
        $self->_post( $request, $response, $c, $original_query_string );
    }

    # Not needed or supported right now, moved to Unneeded module
    # elsif ( $method eq "COPY" ) {
    #     $self->_copy( $request, $response );
    # }
    # elsif ( $method eq "MOVE" ) {
    #     $self->_move( $request, $response );
    # }
    # elsif ( $method eq "MKCOL" ) {
    #     $self->_mkcol( $request, $response, $c );
    # }
    # elsif ( $method eq "LOCK" ) {
    #     $self->_lock( $request, $response );
    # }
    # elsif ( $method eq "UNLOCK" ) {
    #     $self->_unlock( $request, $response );
    # }
    else {
        $response->code(404);
    }

    # This label allows us to quickly abort from any nested function and log + return errors
  QUICKEXIT:

    # Log results of processed request
    $self->_userlog( $request, $response, $c );

    # This is where we return $response to cpdavd to finish the request
    return $response;
}

# This sub handles logging (currently just errors) for the user, as a minimal access style log intended to alert the user to there being a problem
#  so debug logging can be enabled to get details for what is happening.
sub _userlog {
    my ( $self, $request_ref, $response_ref, $c ) = @_;

    # Skip logging if the response code is not in the error range
    if ( $response_ref->code < 400 ) {
        return;
    }
    delete $self->{'smtp_user'};
    delete $self->{'smtp_pass'};

    #     dbg("response: ", $self, $$request_ref, $$response_ref, $c);
    my $req_method  = $request_ref->method();
    my $req_uri     = $request_ref->uri->path;
    my $req_size    = length( $request_ref->content );
    my $resp_status = $response_ref->status_line;
    my $resp_size   = length( $response_ref->content );
    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime(time);
    $year += 1900;
    $mon = (qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/)[$mon];
    my $formatted_time = sprintf( "%02d/%s/%04d:%02d:%02d:%02d", $mday, $mon, $year, $hour, $min, $sec );
    my $log_string     = sprintf(
        '[%s] %s %s "%s %s" %s "%s" %d "%s"',
        $formatted_time       // warn('time missing'),
        $ENV{REMOTE_ADDR}     // warn('remote addr missing'),
        $self->{'username'}   // warn('username missing'),
        $req_method           // warn('req method missing'),
        $req_uri              // warn('req uri missing'),
        $req_size             // warn('req size missing'),
        $resp_status          // warn('resp status missing'),
        $resp_size            // warn('resp size missing'),
        $self->{'request_ua'} // '(none)',
    );

    my $log_file_path = $self->{'acct_homedir'} . '/logs/DAV-error.log';
    my $orig_umask    = umask(0077);
    if ( open( my $user_log_fh, '>>', $log_file_path ) ) {
        print $user_log_fh $log_string . "\n";
        close($user_log_fh);
    }
    else {
        dbg("Error writing to $log_file_path : $!");
    }
    umask($orig_umask);

    $self->_rotate_log($log_file_path);

    # if _rotate_log is bad and not easily fixable, load this module and have it set up and use logrotate on it
    #     my $lr = Cpanel::DAV::CGI::LogRotate->new(
    #         basedir_relative => 'logs',
    #         log_pattern      => 'DAV-*.log',
    #         min_size_k       => 64,
    #         max_size_k       => 6400,
    #     );
    #     $lr->run;
    return;
}

# This sub takes a path for a log file and checks if it is too large, if so, rotates it
sub _rotate_log {
    my ( $self, $log_file ) = @_;
    my $lock_file = $log_file . '.lock';    # the phonetics of these two in the same place is killing me

    my @dir_parts = split( '/', $log_file );
    my $file      = pop(@dir_parts);
    my $base_dir  = join( '/', @dir_parts );

    my $log_file_size = ( stat($log_file) )[7];
    return if !$log_file_size;
    if ( $log_file_size > 5000000 ) {       # around 5MB per log file. 5 older files x 5MB + up to 5MB for current file allows for 25-30MB of data stored in logs. We can tweak this as we see fit, and add a UI for it later if people even care.
        my $lock_time = readlink($lock_file);
        if ( defined $lock_time ) {
            if ( $lock_time =~ m/^\d{10}$/ ) {    # Good through Sat Nov 20 11:46:39 2286
                if ( _time() - $lock_time > 300 ) {    # Locks older than 5 minutes are considered dead while hopefully still give enough buffer for chrony like time adjustments
                    $lock_time = _time();
                    unlink $lock_file;
                    symlink $lock_time, $lock_file or return;
                }
                else {
                    return;
                }
            }
            else {
                # bad lock file ? # Leaving this as a "feature". To get to this point before Y2286 indicates something is very wrong and should be investigated.
                return;
            }
        }
        else {
            $lock_time = _time();
            symlink $lock_time, $lock_file or return;
        }
        opendir( my $base_dir_fh, $base_dir ) or return;
        my @rot_files;
        while ( readdir($base_dir_fh) ) {
            if (m/${file}\-\d{10}$/) {
                push( @rot_files, $_ );
            }
        }
        close($base_dir_fh);
        my $rot_cnt          = @rot_files;
        my @sorted_rot_files = sort(@rot_files);

        # clear old log files
        while ( $rot_cnt > 4 ) {    # keep 5 backups
            my $oldest_rot_file = shift(@sorted_rot_files);
            unlink $base_dir . '/' . $oldest_rot_file or return;    # something already deleted it or it's undeleteable by us
            $rot_cnt = @sorted_rot_files;
        }
        my $new_log_path = $log_file . '-' . int($lock_time);       # Time::HiRes is overriding time() here, so while it's great for the locking, we don't need that level of granularity for the file name
        if ( !-f $new_log_path ) {
            rename $log_file, $new_log_path;                        # very unlikely we'll be on a system that has portability issues with rename()
        }
        unlink $lock_file;
    }
    return;
}

sub _time {
    return time;
}

=head2 get_sharing_for_uri($uri)

Retrieve sharing info (if any) for a given path. This is used internally to check access controls across collections
owned by different users.

See also C<load_sharing()>

=over

=item $uri - The path to check.

=back

=cut

# Note - $uri can be a full fs path, and it can be for a user sharing their calendar with the authenticated user. This covers sharing and proxing (delegates).
sub get_sharing_for_uri {
    my ( $self, $uri ) = @_;
    logfunc();

    dbg("=[get_sharing_for_uri]= : uri = ([$uri])");
    my $path_hr = $self->_parse_request_path($uri);

    my $sharing_hr = $self->load_sharing();

    #     dbg( "=[get_sharing_for_uri]= : self, path_hr and sharing_hr:", $self, $path_hr, $sharing_hr );

    # See if it's a proxy user / delegate wanting to access another principal
    if ( defined( $path_hr->{'principal_user'} ) ) {
        my $proxy_config_hr = $self->load_proxy_config_data();

        if ( length $proxy_config_hr->{ $self->{'request_info'}{'principal_user'} }{ $self->{'auth_user'} } ) {
            my $perm = $proxy_config_hr->{ $self->{'request_info'}{'principal_user'} }{ $self->{'auth_user'} };
            dbg("Found proxy config giving permission : $perm");
            if ( $perm eq 'calendar-proxy-read' ) {

                # $uri_sharing_hr->{ $self->{'auth_user'} } )
                return { $self->{'auth_user'} => 'r' };
            }
            elsif ( $perm eq 'calendar-proxy-write' ) {
                return { $self->{'auth_user'} => 'r,w' };
            }
        }
    }

    # No sense in trying anything further if the request is made to a resource that doesn't relate to a user that can share or be shared with
    #     if ( !defined( $path_hr->{'principal_user'} ) || !defined( $path_hr->{'tags'}{'collection'} ) ) { # relying on 'tags' here breaks on url like /calendars/ttt%40cptech1.test/calendar/2A5314A2-8FBB-45B6-AF88-2C3055631B81.ics
    if ( !defined( $path_hr->{'principal_user'} ) || !defined( $path_hr->{'collection'} ) ) {
        dbg("=[get_sharing_for_uri]= : no principal_user or collection from path_hr, returning undef");
        return undef;
    }
    my $principal_user    = $path_hr->{'principal_user'};
    my $collection_header = $path_hr->{'collection'};

    if ( exists $sharing_hr->{$principal_user} ) {
        if ( exists $sharing_hr->{$principal_user}{$collection_header} ) {
            foreach my $user ( keys %{ $sharing_hr->{$principal_user}{$collection_header} } ) {
                dbg("=[get_sharing_for_uri]=: got $user : $sharing_hr->{$principal_user}{$collection_header}{$user}");
            }
            dbg( "=[get_sharing_for_uri]= : returning whatever this is: ", $sharing_hr->{$principal_user}{$collection_header} );
            return $sharing_hr->{$principal_user}{$collection_header};
        }
    }
    return undef;
}

=head2 save_sharing($data_hr)

Save collection sharing data to C<[homedir]/.caldav/.sharing>. This is a single data structure representing all shared collections
for users belonging to the cPanel account.

=cut

sub save_sharing {
    my ( $self, $data_hr ) = @_;
    logfunc();
    my $privs_obj = _drop_privs_if_needed( $self->{'sys_user'} );

    dbg( "=[save_sharing]= : data_hr and self : ", $data_hr, $self );
    dbg("=[save_sharing]= : ########################### PATH SHOULD BE $self->{'acct_homedir'}/.caldav/.sharing");

    # Convert the nested hash back to our .ini format
    # If "delegator collection" has no shares, remove it to avoid cruft
    my %shared_data_hash;
    foreach my $user ( keys %{$data_hr} ) {
        dbg( "=[save_sharing]= : user is $user and now we look at ", $data_hr->{$user} );
        foreach my $collection ( keys %{ $data_hr->{$user} } ) {
            dbg("=[save_sharing]= : collection is $collection");
            my $sharee_cnt = keys %{ $data_hr->{$user}{$collection} };
            if ($sharee_cnt) {
                $shared_data_hash{ $user . ' ' . $collection } = $data_hr->{$user}{$collection};
            }
            else {
                delete $data_hr->{$user}{$collection};
            }
        }
    }

    dbg( "=[save_sharing]= : sending the following to save_metadata : ", \%shared_data_hash );
    $self->{'metadata'}->save( \%shared_data_hash, $self->{acct_homedir} . '/.caldav/.sharing' );
    return;
}

=head2 load_sharing()

Load collection sharing data from C<[homedir]/.caldav/.sharing>. This is a single data structure representing all shared collections
for users belonging to the cPanel account.

=cut

sub load_sharing {
    my ($self) = @_;
    logfunc();

    # Massage the [user collection] key into a more sensibly nested hash
    dbg( "=[load_sharing]= : load_metadata on ([" . $self->{'acct_homedir'} . '/.caldav/.sharing])' );
    my $raw_sharing_hr = $self->{'metadata'}->load( $self->{'acct_homedir'} . '/.caldav/.sharing' );
    my %sharing_hash;
    foreach my $raw_collection ( keys %{$raw_sharing_hr} ) {
        my ( $user, $collection ) = split( /\s+/, $raw_collection );
        if ( length($user) and length($collection) ) {
            $sharing_hash{$user}{$collection} = $raw_sharing_hr->{$raw_collection};
        }
        else {
            dbg("=[load_sharing]= : failed to parse sharing collection (expected '\$user \$collection'): $raw_collection");
        }
    }

    #     dbg( "=[load_sharing]= : returning : ", \%sharing_hash );
    return \%sharing_hash;
}

sub _options {
    my ( $self, $request, $response ) = @_;
    logfunc();

# Headers returned by CCS :
#   1, access-control, calendar-access, calendar-schedule, calendar-auto-schedule, calendar-availability, inbox-availability, calendar-proxy, calendarserver-private-events, calendarserver-private-comments, calendarserver-sharing, calendarserver-sharing-no-scheduling, calendarserver-group-sharee, calendar-query-extended, calendar-default-alarms, calendar-managed-attachments, calendarserver-partstat-changes, calendarserver-group-attendee, calendar-no-timezone, calendarserver-recurrence-split, addressbook, addressbook, extended-mkcol, calendarserver-principal-property-search, calendarserver-principal-search, calendarserver-home-sync

    # calendar-query-extended is defined in https://www.ietf.org/archive/id/draft-daboo-caldav-extensions-00.txt

# OPTIONS header from /principals/$user/ from CCS :
#   DAV: 1, access-control, calendar-access, calendar-schedule, calendar-auto-schedule, calendar-availability, inbox-availability, calendar-proxy, calendarserver-private-events, calendarserver-private-comments, calendarserver-sharing, calendarserver-sharing-no-scheduling, calendarserver-group-sharee, calendar-query-extended, calendar-default-alarms, calendar-managed-attachments, calendarserver-partstat-changes, calendarserver-group-attendee, calendar-no-timezone, calendarserver-recurrence-split, addressbook, addressbook, extended-mkcol, calendarserver-principal-property-search, calendarserver-principal-search, calendarserver-home-sync

    $response->header( 'DAV'           => '1,2,calendar-access,calendar-schedule,calendar-auto-schedule,calendar-availability,calendar-proxy,resource-sharing,inbox-availability,access-control,addressbook,calendar-managed-attachments,calendarserver-sharing,calendarserver-group-sharee,calendarserver-principal-search,calendarserver-principal-property-search,calendar-free-busy-query' );
    $response->header( 'MS-Author-Via' => 'DAV' );

    # Allow headers from CCS :
    #   ACL, COPY, DELETE, GET, HEAD, LOCK, MKCOL, MOVE, OPTIONS, PROPFIND, PROPPATCH, PUT, REPORT, UNLOCK

    # MKCALENDAR,MKCOL and ACL are explicitly disallowed from libexec/cpdavd , so change that if support is added here
    $response->header( 'Allow'        => 'OPTIONS,PUT,POST,GET,HEAD,DELETE,REPORT,PROPFIND,COPY,MOVE,LOCK,UNLOCK' );    # CCS also has PROPPATCH, ACL (sometimes), REPORT, MKCALENDAR (sometimes)
    $response->header( 'Content-Type' => 'httpd/unix-directory' );
    $response->header( 'Keep-Alive'   => 'timeout=15, max=96' );
    iolog(
        "\n<<<==[ Options Headers Response ]========================================<<<<\n",
        $response->headers(),
    );

    return;
}

sub _head {
    my ( $self, $request, $response ) = @_;
    logfunc();

    my $path = $self->{'request_info'}{'fs_root'};

    if ( -f $path && -r _ ) {
        if ( $self->check_read_access( $request->uri->path ) ) {
            $response->last_modified( ( stat(_) )[9] );
        }
        else {
            $response->code(403);
        }
    }
    elsif ( -d _ ) {
        my @files;
        if ( opendir my $dh, $path ) {
            @files = readdir $dh;
            closedir $dh;
        }
        $response->header( 'Content-Type' => 'text/html; charset="utf-8"' );
    }
    else {
        $response->code(404);
    }

    return;
}

sub _get {
    my ( $self, $request, $response ) = @_;
    logfunc();

    dbg("=[_get]= : entered with request for $request->uri->path");
    my $path = $self->{'request_info'}{'fs_root'};

    if ( -f $path && -r _ ) {
        if ( $self->check_read_access( $request->uri->path ) ) {
            open( my $fh, '<', $path ) or do {
                $response->code(403);    # should be almost unreachable because check_read_access was already called
                $response->message('Forbidden');
                return;
            };
            dbg("=[_get]= : we have access to ([$path]), reading from it now and returning data");
            my $content;
            my $buffer;
            while ( my $length = read $fh, $buffer, 1024 * 1024 ) {

                if ( $length == 0 ) {
                    close $fh;
                }
                else {
                    $content .= $buffer;
                }
            }

            #             dbg("=[_get]= : content is $content"); # if this is binary, like a png attachment, expect your log to be unpretty
            $response->content($content);
            $response->header( 'Etag', $self->_get_etag($path) );    # Required by RC, citing RFC6352 in it's source ( CardDavClient.php )
            $response->last_modified( ( stat(_) )[9] );
            $response->code(200);
            $response->message('OK');
        }
        else {
            $response->code(403);
        }
    }
    elsif ( -d _ ) {

        dbg("=[_get]= : looking at a directory, ([$path])");
        if ( $self->check_read_access( $request->uri->path ) ) {
            my @files;
            if ( opendir my $dh, $path ) {
                @files = readdir $dh;
                closedir $dh;
            }

            my $body;
            foreach my $file (@files) {
                if ( $self->check_read_access( $request->uri->path . "/" . $file ) ) {
                    my $file_last_char = substr $file, -1;
                    if ( -d $path . "/" . $file && $file_last_char ne '/' ) {
                        $body .= qq|<a href="$file/">$file/</a><br>\n|;
                    }
                    else {
                        $file =~ s{/$}{};
                        $body .= qq|<a href="$file">$file</a><br>\n|;
                    }
                    $response->header( 'Content-Type' => 'text/html; charset="utf-8"' );
                    $response->content($body);
                    $response->code(200);
                    $response->message('OK');
                }
                else {
                    $response->code(403);
                }
            }
        }
        else {
            $response->code(403);
        }
    }
    else {
        $response->code(404);
        $response->message('Not Found');
    }

    # This will dump the binary contents of binary attachments to your very not-binary terminal
    #     dbg( "=[_get]= : leaving sub with response size of " . length($response) , $response );
    dbg( "=[_get]= : leaving sub with response size of " . length($response) );

    return;
}

=head2 check_read_access($path)

Given a collection or file path $path, check whether the currently authenticated user has read access, and
return a boolean value indicating the outcome. This could be true if it is owned by the same user or if it
is part of a shared collection.

=cut

sub check_read_access {
    my ( $self, $path ) = @_;
    logfunc();

    #     dbg( "=[check_read_access]= : self and initial path : ", $self, $path );
    dbg("=[check_read_access]= : initial path : ([$path])");
    $path = $self->_safepath($path);
    dbg("=[check_read_access]= : _safepath    : ([$path])");
    my $path_hr = $self->_parse_request_path($path);

    ############################################################################################################################
    # Allow all the things that should be globally readable by anyone (they still have to be authenticated to the server)

    # If the request is in the space of the currently authenticated user, allow it
    if ( length $self->{'auth_user'} && length $path_hr->{'principal_user'} ) {
        if ( $self->{'auth_user'} eq $path_hr->{'principal_user'} ) {
            dbg("=[check_read_access]= : \xe2\x9c\x85 Request is in space for currently authenticated user, allowing.");
            return 1;
        }
        else {
            dbg("=[check_read_access]= : current auth user $self->{'auth_user'} is not the same as the user in the path ([$path_hr->{'principal_user'}])");
        }
    }

    # We want to allow all read access to /principals/*/
    if ( defined( $self->{'request_info'}{'realm'} ) && $self->{'request_info'}{'realm'} eq 'principals' ) {
        dbg("=[check_read_access]= : \xe2\x9c\x85 Request is for /principals/*, allowing.");
        return 1;
    }

    # Always allow access to users' .inbox for availability queries
    if ( $path_hr->{'tags'}{'schedule-inbox'} ) {
        dbg("=[check_read_access]= : \xe2\x9c\x85 Request is for user .inbox, allowing.");
        return 1;
    }

    # If the request is in the space of a different user, load the sharing config and see if access is granted there.
    my $uri_sharing_hr = $self->get_sharing_for_uri($path);
    dbg( "=[check_read_access]= : sharing_hr from URI ([$path]) : ", $uri_sharing_hr );
    my $uri_sharing_for_auth_user = $uri_sharing_hr->{ $self->{'auth_user'} };
    if ( $uri_sharing_for_auth_user && ( $uri_sharing_for_auth_user eq 'r' || $uri_sharing_for_auth_user eq 'r,w' ) ) {
        dbg("=[check_read_access]= : \xe2\x9c\x85 currently authenticated user $self->{'auth_user'} is granted permission to read from ([$path]) via sharing config");
        return 1;
    }

    # Do the same using the proxy config data as well, if still needed.
    my $proxy_config_hr = $self->load_proxy_config_data();
    dbg("=[check_read_access]= : Checking proxy config data");
    my $principal = $self->{'request_info'}{'principal_user'};
    if ( defined $proxy_config_hr->{$principal}{ $self->{'auth_user'} } ) {
        dbg("=[check_read_access]= : \xe2\x9c\x85 currently authenticated user $self->{'auth_user'} is granted permission to read from ([$path]) via proxy config");
        return 1;
    }

    dbg("=[check_read_access]= : \xe2\x9d\x8c returning 0");
    return 0;
}

=head2 check_read_access($path)

NOT CURRENTLY USED

Given a collection or file path $path, check whether the currently authenticated user has write access, and
return a boolean value indicating the outcome. This could be true if it is owned by the same user or if it
is part of a shared collection.

=cut

sub check_write_access {
    my ( $self, $path ) = @_;
    logfunc();
    dbg("=[check_write_access]= : initial path : ([$path])");
    $path = $self->_safepath($path);
    dbg("=[check_write_access]= : _safepath    : ([$path])");
    my $path_hr = $self->_parse_request_path($path);

    dbg( "=[check_write_access]= : Checking write for ([$path]) as $self->{'auth_user'} AND PATH HR:", $path_hr );

    # If the request is in the space of the currently authenticated user, allow it
    if ( $self->{'auth_user'} eq $path_hr->{'principal_user'} ) {
        dbg("=[check_write_access]= : \xe2\x9c\x85 Request is in space for currently authenticated user, allowing.");
        return 1;
    }
    else {
        dbg("=[check_write_access]= : current auth user $self->{'auth_user'} is not the same as the user in the path ([$path_hr->{'principal_user'}])");
    }

    # If the request is in the space of a different user, load the sharing config and see access is granted there
    my $uri_sharing_hr = $self->get_sharing_for_uri($path);
    dbg( "=[check_write_access]= : sharing_hr from URI ([$path]) : ", $uri_sharing_hr );

    if ( $uri_sharing_hr->{ $self->{'auth_user'} } eq 'r,w' ) {
        dbg("=[check_write_access]= : \xe2\x9c\x85 currently authenticated user $self->{'auth_user'} is granted permission to write to ([$path])");
        return 1;
    }

    dbg("=[check_write_access]= : \xe2\x9d\x8c returning 0");
    return 0;
}

=head2 get_user_freebusy_during($attendee, $start, $end)

Given an attendee (user@dom.tld or mailto:user@dom.tld), a dtstart and dtend time, check against the attendee's freebusy
data to see if they are free or not.

This returns an array ref of all events during which the user will be busy within the given period. Each event is marked
by an array ref containing the dtstart and dtend time.

If the attendee cannot be found, it returns undef.

=cut

sub get_user_freebusy_during {
    my ( $self, $attendee, $start, $end ) = @_;
    logfunc();
    $attendee =~ s/^mailto\://;
    dbg("=[get_user_freebusy_during]= : Checking to see if $attendee is free from $start to $end");
    dbg( "=[get_user_freebusy_during]= : self: ", $self );

    # Get a list of available/applicable principals and see if the attendee matches
    my $principals_ar = $self->_get_principals($attendee);
    if ( !defined $principals_ar ) {
        dbg("=[get_user_freebusy_during]= : Could not find attendee -[$attendee]- in list of available principals");
        return undef;
    }

    # If we find a match, load their freebusy.json file
    my $fb_file_path = $self->{'acct_homedir'} . '/.caldav/' . $attendee . '/.freebusy.json';
    dbg("=[get_user_freebusy_during]= : attempting to load freebusy data from ([$fb_file_path])");
    my $fb_data_hr = load_freebusy_data($fb_file_path);
    dbg( "=[get_user_freebusy_during]= : fbdata = ", $fb_data_hr );
    require DateTime;
    require DateTime::Format::Strptime;
    my $strptime = DateTime::Format::Strptime->new(
        pattern   => '%Y%m%dT%H%M%S',
        time_zone => 'UTC'              # Freebusy times should always be UTC afaik
    );
    my @returned_events;
    my $potential_start = $strptime->parse_datetime($start);
    my $potential_end   = $strptime->parse_datetime($end);
    foreach my $collection ( keys %{$fb_data_hr} ) {
        foreach my $event ( keys %{ $fb_data_hr->{$collection} } ) {
            dbg("=[get_user_freebusy_during]= : seeing if $start -> $end is between $fb_data_hr->{$collection}{$event}->{'dtstart'} -> $fb_data_hr->{$collection}{$event}->{'dtend'}");
            my $existing_start = $strptime->parse_datetime( $fb_data_hr->{$collection}{$event}->{'dtstart'} );
            my $existing_end   = $strptime->parse_datetime( $fb_data_hr->{$collection}{$event}->{'dtend'} );
            if ( $potential_start < $existing_end && $potential_end > $existing_start ) {    # if you use <= and >=, it will consider a meeting that ends at 11am conflicting with another meeting that starts at 11am
                dbg("=[get_user_freebusy_during]= : Attendee appears to be busy");
                push( @returned_events, [ $fb_data_hr->{$collection}{$event}->{'dtstart'}, $fb_data_hr->{$collection}{$event}->{'dtend'} ] );
            }
            else {
                dbg("=[get_user_freebusy_during]= : Attendee appears to be free for this particular time set");
            }
        }
    }
    return \@returned_events;
}

=head2 get_user_availability_during($attendee, $start, $end)

Given an attendee (user@dom.tld or mailto:user@dom.tld), a dtstart and dtend time, check against the attendee's availability
data to see if they are available or not.

This returns an array ref of all B<unavailable> times within the given period.

If the attendee cannot be found, it returns undef.

=cut

sub get_user_availability_during {
    my ( $self, $attendee, $search_start, $search_end ) = @_;
    logfunc();
    $attendee =~ s/^mailto\://i;
    my $principals_ar = $self->_get_principals($attendee);
    if ( !defined $principals_ar ) {
        dbg("=[get_user_availability_during]= : Could not find attendee -[$attendee]- in list of available principals");
        return undef;
    }
    dbg("=[get_user_availability_during]= : $attendee : Client searching from start($search_start) through end($search_end)");

    require DateTime;
    require DateTime::Format::Strptime;
    require DateTime::TimeZone;
    my $strptime = DateTime::Format::Strptime->new(
        pattern => '%Y%m%dT%H%M%S',
    );

    my $search_start_dt = $strptime->parse_datetime($search_start);
    my $search_end_dt   = $strptime->parse_datetime($search_end);
    dbg( "=[get_user_availability_during]= : Client search date/time: " . $search_start_dt->strftime('%Y-%m-%dT%H:%M:%S%z') . ' -> ' . $search_end_dt->strftime('%Y-%m-%dT%H:%M:%S%z') );

    my @unavailable_times;
    my $availability_card;
    my $availability_file_path = $self->{'acct_homedir'} . '/.caldav/' . $attendee . '/.availability';

    # if( open(my $avail_fh,'<', $self->{'request_info'}{'fs_base_principal_path'} . '.availability') ) {
    if ( open( my $avail_fh, '<', $availability_file_path ) ) {
        while (<$avail_fh>) {
            $availability_card .= $_;
        }
        close($avail_fh);

        my $parsed_vcard_hr;
        eval { $parsed_vcard_hr = Text::VCardFast::vcard2hash($availability_card); };
        if ($@) {
            dbg( "=[get_user_availability_during]= : failed to parse VCARD: ", $@, $availability_card );
            return [];
        }

        # dbg("=[get_user_availability_during]= : parsed availability_card:", $parsed_vcard_hr );
        foreach my $vcalendar ( @{ $parsed_vcard_hr->{'objects'} } ) {
            if ( $vcalendar->{'type'} eq 'vcalendar' ) {
                foreach my $section ( @{ $vcalendar->{'objects'} } ) {

                    # dbg("=[get_user_availability_during]= : vcalendar section:", $section );
                    if ( $section->{'type'} eq 'vavailability' ) {

                        # dbg("=[get_user_availability_during]= : found vavailability section:", $section );
                        foreach my $subsection ( @{ $section->{'objects'} } ) {
                            if ( $subsection->{'type'} eq 'available' ) {

                                # dbg("=[get_user_availability_during]= : found available section:", $subsection->{'properties'} );
                                dbg("=[get_user_availability_during]= : /[found server config section : --------------------------------------]/");

                                my $rrule        = $subsection->{'properties'}{'rrule'}[0]{'value'};
                                my $dtstart      = $subsection->{'properties'}{'dtstart'}[0]{'value'};
                                my $dtstart_tzid = $subsection->{'properties'}{'dtstart'}[0]{'params'}{'tzid'}[0];
                                my $dtend        = $subsection->{'properties'}{'dtend'}[0]{'value'};
                                my $dtend_tzid   = $subsection->{'properties'}{'dtend'}[0]{'params'}{'tzid'}[0];
                                my $dtstamp      = $subsection->{'properties'}{'dtstamp'}[0]{'value'};

                                $dtstart_tzid = _fix_tzid_if_needed($dtstart_tzid);
                                $dtend_tzid   = _fix_tzid_if_needed($dtend_tzid);

                                dbg("=[get_user_availability_during]= : server config start = $dtstart ($dtstart_tzid), end = $dtend ($dtend_tzid) , stamped $dtstamp , rrule $rrule");

                                # Take the date from the DTSTAMP when applying the TZID, so we can calculate the timezones/offsets accurately
                                my $avail_dtstamp_dt       = $strptime->parse_datetime($dtstamp);
                                my $avail_start_dtstamp_dt = $avail_dtstamp_dt->set_time_zone( DateTime::TimeZone->new( name => $dtstart_tzid ) );
                                my $avail_end_dtstamp_dt   = $avail_dtstamp_dt->set_time_zone( DateTime::TimeZone->new( name => $dtend_tzid ) );

                                # Get timezone objects of the DTSTAMP
                                my $dtstamp_start_timezone_object = $avail_start_dtstamp_dt->time_zone;
                                my $dtstamp_end_timezone_object   = $avail_end_dtstamp_dt->time_zone;

                                # This is the offset for the DTSTAMP, which indicates the intended times rather than using the offset for the DTSTART/DTEND dates, which are basically
                                # arbitrary for this situation.
                                my $dtstamp_start_offset_secs = $dtstamp_start_timezone_object->offset_for_datetime($avail_dtstamp_dt);
                                my $dtstamp_end_offset_secs   = $dtstamp_end_timezone_object->offset_for_datetime($avail_dtstamp_dt);
                                dbg("=[get_user_availability_during]= : dtstamp start OFFSET : _[$dtstamp_start_offset_secs]_");
                                dbg("=[get_user_availability_during]= : dtstamp end OFFSET : _[$dtstamp_end_offset_secs]_");

                                # Get the DTSTART object in sync with the offset from DTSTAMP
                                my $avail_dtstart_dt      = $strptime->parse_datetime($dtstart);
                                my $avail_dtstart_tzid_dt = DateTime::TimeZone->new( name => $dtstart_tzid );
                                $avail_dtstart_dt->set_time_zone($avail_dtstart_tzid_dt);    # set original timezone so when we set it to UTC right after, it knows how to calculate it
                                my $dtstart_timezone_object = $avail_dtstart_dt->time_zone;
                                my $dtstart_offset_secs     = $dtstart_timezone_object->offset_for_datetime($avail_dtstart_dt);
                                if ( $dtstart_offset_secs != $dtstamp_start_offset_secs ) {
                                    dbg("=[get_user_availability_during]= : [START] Offsets mismatch b/t DTSTAMP _[$dtstamp_start_offset_secs]_ and DTSTART _[$dtstart_offset_secs]_, we need to get DTSTART in sync");
                                    my $difference_secs = $dtstamp_start_offset_secs - $dtstart_offset_secs;
                                    dbg("=[get_user_availability_during]= : [START] Offset difference : $difference_secs");
                                    $avail_dtstart_dt->subtract( seconds => $difference_secs );
                                    my $new_offset = $dtstart_timezone_object->offset_for_datetime($avail_dtstart_dt);
                                    dbg("=[get_user_availability_during]= : [START] Resulting offset : _[$new_offset]_");
                                }
                                $avail_dtstart_dt->set_time_zone('UTC');                     # convert the (now) correct/intended time to UTC to make the datetime math logic less painful

                                # Get the DTEND object in sync with the offset from DTSTAMP
                                my $avail_dtend_dt      = $strptime->parse_datetime($dtend);
                                my $avail_dtend_tzid_dt = DateTime::TimeZone->new( name => $dtend_tzid );
                                $avail_dtend_dt->set_time_zone($avail_dtend_tzid_dt);
                                my $dtend_timezone_object = $avail_dtend_dt->time_zone;
                                my $dtend_offset_secs     = $dtend_timezone_object->offset_for_datetime($avail_dtend_dt);
                                if ( $dtend_offset_secs != $dtstamp_end_offset_secs ) {
                                    dbg("=[get_user_availability_during]= : [END] Offsets mismatch b/t DTSTAMP _[$dtstamp_end_offset_secs]_ and DTEND _[$dtend_offset_secs]_, we need to get DTEND in sync");
                                    my $difference_secs = $dtstamp_end_offset_secs - $dtend_offset_secs;
                                    dbg("=[get_user_availability_during]= : [END] Offset difference : $difference_secs");
                                    $avail_dtend_dt->subtract( seconds => $difference_secs );
                                    my $new_offset = $dtstart_timezone_object->offset_for_datetime($avail_dtend_dt);
                                    dbg("=[get_user_availability_during]= : [END] Resulting offset : _[$new_offset]_");
                                }
                                $avail_dtend_dt->set_time_zone('UTC');

                                dbg( "=[get_user_availability_during]= : server config parse = " . $avail_dtstart_dt->strftime('%Y-%m-%dT%H:%M:%S%z') . ", end = " . $avail_dtend_dt->strftime('%Y-%m-%dT%H:%M:%S%z') . ", rrule $rrule" );

                                my %rrule_parts;
                                foreach my $part ( split /;/, $rrule ) {
                                    my ( $key, $value ) = split /=/, $part, 2;
                                    $rrule_parts{$key} = $value;
                                }

                                #      - RRULEs can get surprisingly complex, and we'll likely want to add https://metacpan.org/pod/DateTime::TimeZone::ICal into the mix
                                #        to help manage it. For now we try to cover the most common scenarios. See also https://www.nylas.com/blog/calendar-events-rrules/
                                #        and https://jkbrzt.github.io/rrule/
                                #      - this currently only supports FREQ=WEEKLY and BYDAY, which is what the Apple Calendar uses
                                my $freq     = $rrule_parts{'FREQ'};
                                my @bydays   = split /,/, $rrule_parts{'BYDAY'};
                                my $interval = $rrule_parts{'INTERVAL'};    # Unused reminder
                                my $count    = $rrule_parts{'COUNT'};       # Unused reminder
                                dbg("=[get_user_availability_during]= : freq = $freq, bydays = @bydays");

                                # Please be English only..
                                my %ughly_abbr_table;
                                $ughly_abbr_table{'MO'} = 'Mon';
                                $ughly_abbr_table{'TU'} = 'Tue';
                                $ughly_abbr_table{'WE'} = 'Wed';
                                $ughly_abbr_table{'TH'} = 'Thu';
                                $ughly_abbr_table{'FR'} = 'Fri';
                                $ughly_abbr_table{'SA'} = 'Sat';
                                $ughly_abbr_table{'SU'} = 'Sun';

                                for my $byday (@bydays) {

                                    my $current_date = $search_start_dt->clone;
                                    my $last_date    = $search_end_dt->clone;

                                    dbg( "=[get_user_availability_during]= : looking for a -[$ughly_abbr_table{$byday}]- on days between " . $current_date->ymd . ' and ' . $last_date->ymd );

                                    while ( $current_date < $last_date ) {
                                        dbg( "=[get_user_availability_during]= : -=?=- " . $current_date->strftime('%Y-%m-%dT%H:%M:%S%z') . " is a " . $current_date->day_abbr );
                                        if ( $current_date->day_abbr eq $ughly_abbr_table{$byday} ) {
                                            dbg( "=[get_user_availability_during]= : ![found a match for byday]! : current_date " . $current_date->strftime('%Y-%m-%dT%H:%M:%S%z') );

                                            # We just want to return the unavailable times on this day. doing it this way may return some time before or after the specified start time, but
                                            # the client should still parse this fine.

                                            # Note that we often set the timezone twice, once to whatever/UTC and again whatever/UTC ; the first call defines what it is, the second call will change it and alter the time itself

                                            my $current_date_start = $current_date->clone->set(
                                                year   => $current_date->year,
                                                month  => $current_date->month,
                                                day    => $current_date->day,
                                                hour   => 0,
                                                minute => 0,
                                                second => 0,
                                            );
                                            $current_date_start->set_time_zone($avail_dtstart_tzid_dt);
                                            $current_date_start->set_time_zone('UTC');

                                            my $current_date_end = $current_date->clone->set(
                                                year   => $current_date->year,
                                                month  => $current_date->month,
                                                day    => $current_date->day,
                                                hour   => 23,
                                                minute => 59,
                                                second => 59,
                                            );
                                            $current_date_end->set_time_zone($avail_dtend_tzid_dt);
                                            $current_date_end->set_time_zone('UTC');

                                            my $available_date_start = $current_date->clone->set(
                                                year   => $current_date->year,
                                                month  => $current_date->month,
                                                day    => $current_date->day,
                                                hour   => $avail_dtstart_dt->hour,
                                                minute => $avail_dtstart_dt->minute,
                                                second => $avail_dtstart_dt->second,
                                            );
                                            $available_date_start->set_time_zone($avail_dtstart_tzid_dt);

                                            my $available_date_end = $current_date->clone->set(
                                                year   => $current_date->year,
                                                month  => $current_date->month,
                                                day    => $current_date->day,
                                                hour   => $avail_dtend_dt->hour,
                                                minute => $avail_dtend_dt->minute,
                                                second => $avail_dtend_dt->second,
                                            );
                                            $available_date_end->set_time_zone($avail_dtend_tzid_dt);

                                            my $current_date_start_str = $current_date_start->clone->strftime('%Y%m%dT%H%M%SZ');
                                            my $current_date_end_str   = $current_date_end->clone->strftime('%Y%m%dT%H%M%SZ');

                                            my $available_start_str = $available_date_start->clone->strftime('%Y%m%dT%H%M%SZ');
                                            my $available_end_str   = $available_date_end->clone->strftime('%Y%m%dT%H%M%SZ');

                                            dbg("=[get_user_availability_during]= : adding start of day block $current_date_start_str -> $available_start_str to unavailable times");
                                            push @unavailable_times, $current_date_start_str . '/' . $available_start_str;
                                            dbg("=[get_user_availability_during]= : adding end of day block $available_end_str -> $current_date_end_str to unavailable times");
                                            push @unavailable_times, $available_end_str . '/' . $current_date_end_str;

                                        }
                                        else {
                                            dbg( "=[get_user_availability_during]= : no match b/t " . $current_date->day_abbr . " and $ughly_abbr_table{$byday}" );
                                        }
                                        $current_date->add( days => 1 );
                                        dbg( "=[get_user_availability_during]= : starting next loop (?) iteration with current_date set to " . $current_date->ymd );
                                    }
                                }
                                dbg("=[get_user_availability_during]= : done with while loop");
                            }
                        }
                    }
                }
            }
        }
    }
    return \@unavailable_times;
}

# Given $attendee string and VCardFast parsed vfreebusy hash ref, get the raw vcard back
sub _generate_freebusy_vcard {
    my ( $self, $attendee, $parsed_vcard_hr, $matching_freebusy_events_ar, $user_availability_ar ) = @_;
    logfunc();
    dbg( "=[_generate_freebusy_vcard]= : parsed vcard, freebusy events and availability: ", $parsed_vcard_hr, $matching_freebusy_events_ar, $user_availability_ar );

    my $fairly_static_vcard = <<~"EOVCARD";
    BEGIN:VCALENDAR
    VERSION:2.0
    METHOD:REPLY
    PRODID:$prodid
    BEGIN:VFREEBUSY
    UID:$parsed_vcard_hr->{'uid'}{'value'}
    DTSTART:$parsed_vcard_hr->{'dtstart'}{'value'}
    DTEND:$parsed_vcard_hr->{'dtend'}{'value'}
    ATTENDEE:$attendee
    DTSTAMP:$parsed_vcard_hr->{'dtstamp'}{'value'}
    ORGANIZER:$parsed_vcard_hr->{'organizer'}{'value'}
    EOVCARD

    foreach my $timeblock ( @{$user_availability_ar} ) {
        $fairly_static_vcard .= "FREEBUSY;FBTYPE=BUSY-UNAVAILABLE:$timeblock\n";
    }

    foreach my $event_ar ( @{$matching_freebusy_events_ar} ) {
        my ( $start, $end ) = @{$event_ar};
        $fairly_static_vcard .= "FREEBUSY;FBTYPE=BUSY:$start/$end\n";
    }

    $fairly_static_vcard .= <<~'EOVCARDCLOSE';
    END:VFREEBUSY
    END:VCALENDAR
    EOVCARDCLOSE

    return $fairly_static_vcard;
}

# rfc8607
sub _post {    ##no critic(Subroutines::ProhibitExcessComplexity)
    my ( $self, $request, $response, $c, $original_query_string ) = @_;
    logfunc();

    # dbg( "=[_post]= : handling POST request, we need to find the args ($original_query_string) ?", $self, $request, $c );

    # HB-7218 - small - At some point we may need to split $original_query_string into array to handle query strings like action=attachment-update&managed-id=97S
    my $path = $self->{'request_info'}{'fs_root'};
    dbg("=[_post]= : path = ([$path])");
    my $content = $request->content();
    dbg( "=[_post]= : content is " . length($content) . " bytes" );
    my $headers_obj = $request->headers();
    dbg( "=[_post]= : headers are:", $headers_obj );

    dbg("=[_post]= : Checking if the client claims this is a chunked encoded transfer..");
    if ( !length( $headers_obj->header('Transfer-Encoding') ) || lc( $headers_obj->header('Transfer-Encoding') ) ne 'chunked' ) {
        dbg("=[_post]= : Missing Transfer-Encoding: chunked header.. if we have \$content, we can still try to write it");
        if ($content) {
            dbg( "=[_post]= : We have \$content, size is " . length($content) );

            # freebusy requests are often made via POST messages to a principal's .outbox/ or attendee's .inbox/ with a Content-type of text/calendar , content being a minimal iTIP style event file.
            if ( index( $headers_obj->{'content-type'}, 'text/calendar' ) >= 0 ) {
                dbg("=[_post]= : looks like a freebusy request based on Content-type alone..");

                # HB-7219 - medium - break this out into something like sub parse_itip_data() ?

                # Go ahead and start our response doc up here
                my $doc = XML::LibXML::Document->new( "1.0", "utf-8" );
                $response->header( 'Content-Type' => 'text/xml; charset="UTF-8"' );

                my $parsed_freebusy_hr = $self->parse_itip_data( \$content );
                dbg( "=[_post]= : parsed content: ", $parsed_freebusy_hr );
                my $found_freebusy = 0;
                foreach my $entry ( @{$parsed_freebusy_hr} ) {
                    if ( !defined $entry->{'vfreebusy'} ) {
                        dbg("=[_post]= : does not appear to be a freebusy section");
                        next;
                    }
                    dbg( "=[_post]= : DOES appear to be a freebusy section: ", $entry );
                    $found_freebusy++;
                    my $dtstart_time = $entry->{'vfreebusy'}{'dtstart'}{'value'};
                    my $dtend_time   = $entry->{'vfreebusy'}{'dtend'}{'value'};

                    my $schedule_response_el = $doc->createElement('C:schedule-response');
                    $schedule_response_el->setAttribute( 'xmlns:D', 'DAV:' );
                    $schedule_response_el->setAttribute( 'xmlns:C', 'urn:ietf:params:xml:ns:caldav' );

                    foreach my $attendee_section ( @{ $entry->{'vfreebusy'}{'attendee'} } ) {
                        my $attendee = $attendee_section->{'value'};
                        dbg("=[_post]= : checking to see if $attendee is available between $dtstart_time and $dtend_time");

                        my $response_el  = $doc->createElement('C:response');
                        my $recipient_el = $doc->createElement('C:recipient');
                        my $href_el      = $doc->createElement('D:href');
                        $href_el->appendText($attendee);
                        $recipient_el->addChild($href_el);
                        $response_el->addChild($recipient_el);

                        my $matching_freebusy_events_ar = $self->get_user_freebusy_during( $attendee, $dtstart_time, $dtend_time );
                        if ( !defined $matching_freebusy_events_ar ) {
                            dbg("=[_post]= : attendee $attendee not found in available principals list??");
                            my $response_el  = $doc->createElement('C:response');
                            my $recipient_el = $doc->createElement('C:recipient');
                            my $href_el      = $doc->createElement('D:href');
                            $href_el->appendText($attendee);
                            $recipient_el->addChild($href_el);
                            $response_el->addChild($recipient_el);
                            my $request_status_el = $doc->createElement('C:request-status');
                            $request_status_el->appendText('3.7;Invalid calendar user');
                            $response_el->addChild($request_status_el);
                        }
                        else {
                            dbg("=[_post]= : building user is FREE response ");

                            my $request_status_el = $doc->createElement('C:request-status');
                            $request_status_el->appendText('2.0;Success');
                            $response_el->addChild($request_status_el);
                            my $calendar_data_el = $doc->createElement('C:calendar-data');

                            my $user_availability_ar = $self->get_user_availability_during( $attendee, $dtstart_time, $dtend_time );
                            my $calendar_data        = $self->_generate_freebusy_vcard( $attendee, $entry->{'vfreebusy'}, $matching_freebusy_events_ar, $user_availability_ar );

                            my $text_node = XML::LibXML::CDATASection->new($calendar_data);
                            $calendar_data_el->addChild($text_node);
                            $response_el->addChild($calendar_data_el);

                            my $resp_desc_el = $doc->createElement('D:responsedescription');
                            $resp_desc_el->appendText('OK');
                            $response_el->addChild($resp_desc_el);

                            $schedule_response_el->addChild($response_el);
                        }
                    }
                    $doc->addChild($schedule_response_el);
                }
                if ($found_freebusy) {
                    $response->code(200);
                    $response->message('OK');
                    $response->content( $doc->toString(1) );

                }
                else {
                    $response->code(400);
                    $response->message('Bad Request');
                    dbg( "=[_post]= : !!!!!!!!! ![failed to find vfreebusy in POSTed VCARD content]! :", $@, $content, $parsed_freebusy_hr );
                }
                iolog(
                    "\n<<<==[ Response ]===============================================<<<<\n",
                    $response->content() . "\n",
                    "<<<==[ End Response ]===========================================<<<<",
                );
                return;
            }

            # the content-type header can sometimes be something like "application/xml; charset=utf-8" , so we look for the relevant part
            elsif ( index( $headers_obj->{'content-type'}, 'text/xml' ) >= 0 or index( $headers_obj->{'content-type'}, 'application/xml' ) >= 0 ) {

                # HB-7220 - medium , possibly - determine proper security controls on who gets to write what where. There's a lot of ACLs that can come into play here.
                # parse the xml into an object
                my $parser = XML::LibXML->new;
                my $payload_xml;
                eval { $payload_xml = $parser->parse_string($content); };
                if ($@) {
                    $response->code(400);
                    $response->message('Bad Request');
                    dbg( "=[_post]= : !!!!!!!!! ![failed to parse XML content]! :", $@, $content );
                    goto QUICKEXIT;
                }
                dbg( "=[_post]= : payload_xml:", $payload_xml );

                my $reqtype = $payload_xml->find('/*')->shift->localname;
                dbg("=[_post]= : reqtype = $reqtype");

                # if it's a "share", handle it. HB-7220 - medium - good place to break this section out and refactor into module/subroutine, in the end.
                if ( $reqtype eq 'share' ) {
                    for my $node ( $payload_xml->find('/*/*')->get_nodelist ) {
                        my $share_action = $node->localname;
                        dbg("=[_post]= : share action = $share_action\n$node");
                        my @share_action_nodes = $node->childNodes();

                        # Build a list of possible/known/expected types. We mainly care about href, common-name and read or read-write
                        my $san_href = '';
                        my $san_cn   = '';
                        my $san_perm = '';
                        foreach my $san (@share_action_nodes) {
                            my $san_ln = $san->localname();
                            if ($san_ln) {
                                my $san_value = $san->textContent();
                                my $san_nsuri = $san->namespaceURI();
                                dbg("=[_post]= : Found element of $san_ln eq to $san_value in namespace $san_nsuri");
                                if ( $san_ln eq 'href' ) {
                                    $san_href = $san_value;
                                }
                                elsif ( $san_ln eq 'common-name' ) {
                                    $san_cn = $san_value;
                                }
                                elsif ( $san_ln eq 'read' ) {
                                    $san_perm = 'r';
                                }
                                elsif ( $san_ln eq 'read-write' ) {
                                    $san_perm = 'r,w';
                                }
                                else {
                                    dbg("_post: ignoring unhandled shared action node : $san_ln = $san_value , ns $san_nsuri");
                                }
                            }
                        }

                        my $collection = $self->{'request_info'}{'collection'};

                        # The $san_href at this point can be an email, "user@dom.tld" , an html anchor "mailto:user@dom.tld" or a principal-URL, like "/principals/user@dom.tld/" or even "https://princ_user%40dom.tld@dom.tld:2080/principals/user%40dom.tld"
                        # We want to ensure we are working with just the email address regardless of the format given.

                        if ( $san_href =~ m/^mailto:(.+\@.+)$/i ) {
                            $san_href = $1;
                        }
                        elsif ( $san_href =~ m{/principals/([^/]+)/?} ) {
                            $san_href = $1;
                            $san_href =~ s/%40/\@/;
                        }
                        dbg("=[_post]= : san_href is ($san_href)");

                        # At this point we should have just an email account/user, otherwise it's probably bad data
                        # HB-6846 - how does this work IRL when the /principals/$user/ is the system $user ?
                        if ( !Cpanel::Validate::EmailRFC::is_valid_remote($san_href) ) {
                            $response->code(400);
                            $response->message('Bad Request');
                            dbg("=[_post]= : \xe2\x9d\x97\xe2\x9d\x97\xe2\x9d\x97 ![Could not get valid email from ($san_href), skipping this action]! \xe2\x9d\x97\xe2\x9d\x97\xe2\x9d\x97");
                            next;    # If this is encounted in the wild, we may want to consider this to be fatal, overall, and goto QUICKEXIT. We'd need to be able to reproduce it, however.
                        }

                        # for each "set", load sharing data, modify it to include the new href user, then save it. Need to handle mailto:email@addr.ess or princpal-URL as well as common-name
                        if ( $share_action eq 'set' ) {
                            if ( !$san_href || !$san_perm ) {
                                dbg("=[_post]= : client wants to set a new share, but we are missing either the href($san_href) or perm($san_perm)");
                                next;
                            }
                            dbg("=[_post]= : saving new share of $san_perm to $san_href");

                            my $sharing_hr = $self->load_sharing();
                            $sharing_hr->{ $self->{'auth_user'} }{$collection}{$san_href} = $san_perm;
                            $self->save_sharing($sharing_hr);

                            # for each "remove", load sharing data, remove href user from collection, then save it
                        }
                        elsif ( $share_action eq 'remove' ) {
                            if ( !$san_href ) {
                                dbg("=[_post]= : client wants to remove an existing share, but we are missing the href($san_href)");
                                next;
                            }
                            dbg("=[_post]= : removing share from $san_href");
                            my $sharing_hr = $self->load_sharing();
                            delete $sharing_hr->{ $self->{'auth_user'} }{$collection}{$san_href};
                            $self->save_sharing($sharing_hr);

                        }
                        else {
                            dbg("=[_post]= : got an unknown share action type: $share_action . Expected set or remove.");
                            $response->message("Invalid request");
                            $response->code(400);
                            goto QUICKEXIT;
                        }
                    }
                }
                else {
                    dbg("=[_post]= : got XML content, but reqtype is $reqtype which is not yet handled.");
                    return;
                }
            }
            else {
                dbg( "=[_post]= : request with content, but not a text/xml content type (" . $headers_obj->{'content-type'} . "), so not sure how to handle it.." );

                # For now, assume it's a binary attachment ? that's the only thing seen in the wild so far
                # The main problem is we don't know what to name the file to write to. If we have content-disposition we can get it from there. If we don't have that,
                # we'll have to see if the file exists. We don't want to overwrite an existing .ics file with something that meant to be an attachment.
                # For now, consider this a bad request
                $response->message("Invalid request");    # Sir, this is a Wendy's
                $response->code(400);
                goto QUICKEXIT;
            }
        }
        else {
            # If we don't have the POST $content, we need to read it off the wire and process it
        }
    }
    else {
        dbg("=[_post]= : We have a Transfer-Encoding: chunked header");

        if ( !length $headers_obj->header('content-disposition') ) {

            # Reject the POST attempt if it is something we don't handle.
            dbg("=[_post]= : no content and no content-disposition header, not accepting this POST request.");
            $response->message("Invalid request");    # Sir, this is a Wendy's
            $response->code(400);
            goto QUICKEXIT;
        }

        dbg("=[_post]= : Verifying the client claims this is a chunked encoded transfer..");
        if ( $headers_obj->header('Transfer-Encoding') !~ /^chunked$/i ) {
            dbg("=[_post]= : Missing Transfer-Encoding: chunked header.. if we have $content, we can still try to write it");
        }

        # Get the info we need from the Content-Disposition header
        my (@post_dispo)        = split( /;/, $headers_obj->header('content-disposition') );
        my $post_dispo_type     = '';
        my $post_dispo_filename = '';
        my $post_dispo_size     = '';

        # We ignore inline, creation-date and modification-date , fwiw

        foreach my $post_dispo (@post_dispo) {
            $post_dispo =~ s/(^\s+|\s$)//g;
            dbg("=[_post]= : post_dispo = $post_dispo");
            if ( $post_dispo =~ m/=/ ) {
                my ( $key, $val ) = split( /=/, $post_dispo, 2 );
                $val =~ s/(^\"|\"$)//g;
                if ( $key eq 'filename' ) {
                    $post_dispo_filename = $val;
                }
                elsif ( $key eq 'size' ) {
                    $post_dispo_size = $val;
                }
                else {
                    dbg("=[_post]= : Encountered an unhandled Content-Disposition header element: $post_dispo");
                }
            }
            else {
                $post_dispo_type = $post_dispo;
            }
        }

        my $post_file_type = $headers_obj->header('content-type');

        # If we have a filename from the content-disposition header, use that, otherwise use the file name from the request url path
        my $filename = $post_dispo_filename;
        if ( !$filename ) {
            my @path_parts = split( /\//, $path );
            $filename = pop @path_parts;
        }
        dbg("=[_post]= : filename is $filename, post_dispo_filename is $post_dispo_filename");
        dbg("=[_post]= : file type is $post_file_type");

        # Either we write directly to the file, or if it's an attachment, assume it is for a vcard/vevent file and alter the path accordingly
        my $data_path = $path;
        dbg("=[_post]= : data_path at this point is ([$data_path])");
        my $managed_id = '';

        if ( $post_dispo_type eq 'attachment' ) {
            require Cpanel::Rand::Get;
            $managed_id = Cpanel::Rand::Get::getranddata(20);

            # If the day comes where we need to easily/quickly locate an attachment without knowing the principal and collection, consider storing the $managed_id in an account-wide index file
            # so we don't have to scan the entire .caldav/ space for it, which would be too resource prohbitive.
            dbg("=[_post]= : managed id is $managed_id");
            $data_path = $path . '-attachment-' . $managed_id . '-' . MIME::Base64::encode_base64( $filename, '' );
        }
        else {
            dbg("=[_post]= : post_dispo_type is not attachment, but $post_dispo_type, so data_path is not being changed..");
        }

        dbg("=[_post]= : attachment path is $data_path");

        if ( $self->check_write_access( $request->uri->path ) ) {    # this is a placeholder for ACLs, not a permissions check. this also assumes $data_path is given same access as request path
            dbg( "=[_post]= : we have write access to " . $request->uri->path );

            # Check size offered by the client against our limit.
            my $contentlength = $request->header("Content-Length");    # Not guaranteed to be here, so make sure a null value is ok in checks using it
            dbg("=[_post]= : contentlength is claimed to be '$contentlength' by the client");
            if ( $self->check_if_over_upload_limit( $response, $contentlength ) ) {
                return;
            }

            # At this point we've already run the path through check_write_access, which should cover all allowed users.
            my $un_chunked_content;
            my $orig_umask = umask(0077);
            if ( open my $fh, '>', $data_path ) {
                dbg("=[_post]= : created file at $data_path");
                my $total_bytes = length($content);
                dbg("=[_post]= : size of content going into chunked reader: $total_bytes");
                while ( my $line = <$c> ) {
                    dbg("=[_post]= : marker 0 ($line))");
                    if ( $self->check_if_over_upload_limit( $response, $total_bytes ) ) {
                        close($fh);
                        unlink $data_path;
                        return;
                    }
                    dbg("=[_post]= : marker 1");
                    last if $line eq "0\r\n";    # End of chunked data
                    dbg("=[_post]= : marker 2");
                    my ($chunk_size) = $line =~ /^([0-9a-fA-F]+)/;
                    next if !defined $chunk_size;
                    dbg("=[_post]= : marker 3 chunk size: $chunk_size");
                    my $chunk_data = '';
                    my $bytes_read = 0;

                    while ( defined $chunk_size && $bytes_read < hex($chunk_size) ) {
                        my $data;
                        dbg("=[_post]= : marker 4 bytes read: $bytes_read");
                        my $bytes = $c->read( $data, hex($chunk_size) - $bytes_read );
                        dbg("=[_post]= : marker 5 bytes: $bytes");
                        last unless $bytes;    # End of stream
                        dbg("=[_post]= : marker 6");
                        $chunk_data .= $data;
                        $bytes_read  += $bytes;
                        $total_bytes += $bytes_read;
                    }
                    $un_chunked_content .= $chunk_data;

                    #                     $content .= $chunk_data; # Saving in case ignoring what is already in $content is bad, same with print $fh $content line below

                }
                print $fh $un_chunked_content;

                #                 print $fh $content;

                #             # This doesn't work with transfer-encoding: Chunked, so we have to read it off the wire

                #             my $buffer;
                #             my $contentlength = $request->header("Content-Length"); # This might not exist, so try to figure out why
                #             my $contentlength = $headers_obj->content_length();
                #             dbg("POST contentlength is $contentlength");
                #             while ( $contentlength > 0 ) {
                #
                #                 # read a chunk of data into buffer
                #                 my $length = $c->read( $buffer, _min( 1024 * 1024, $contentlength ) );
                #                 dbg("POST length = $length ($buffer)");
                #                 if ( $length > 0 ) {
                #                     my $buf_type = ref $buffer;
                #                     iolog(">>>==[ POST PAYLOAD TYPE REF: $buf_type ]\n");
                #                     iolog(">>>==[ POST PAYLOAD ]=============================================\n$buffer\n");
                #                     print $fh $buffer;
                #                     $contentlength -= $length;
                #                 }
                #                 else {
                #                     select( undef, undef, undef, 0.25 );    # TODO - make this less dumb / prone to waiting on a dead buffer
                #                 }
                #             }
                close $fh;
                dbg("=[_post]= : Content written to ([$data_path])");

                # If this was an attachment, modify the related vcard/vevent
                if ( $post_dispo_type eq 'attachment' && $filename ) {    # HB-7218 - small - check if we have action=attachment-add or action=attachment-update&managed-id=97S , etc in the $original_query_string
                    $self->_modify_event( 'add', 'attachment', $request, $path, $data_path, $filename, $post_file_type, $total_bytes, $managed_id );
                    $response->header( 'Cal-Managed-Id' => $managed_id );
                    $response->header( 'Etag'           => $self->_get_etag($data_path) );
                    my $url = 'https://' . $request->{'_headers'}{'host'} . Cpanel::Encoder::URI::uri_encode_dirstr( $self->{'request_info'}{'uri_decoded_safe'} . '-attachment-' . $managed_id . '-' . MIME::Base64::encode_base64( $filename, '' ) );
                    $response->header( 'Location' => $url );
                }

                $response->code(201);
                $response->message("CREATED");
            }
            else {
                dbg("=[_post]= : can not write to ([$data_path])");
                $response->code(403);
            }
            umask($orig_umask);
        }
        else {
            dbg("=[_post]= : returning 403 because check_write_access returned NOPE");
            $response->code(403);
        }
    }
    dbg( "=[_post]= : full POST response: ", $response );
    return;
}

=head2 fold_string($str, $max_len)

Wrap long strings in $str to conform to the VCARD format. Each line in a VCARD is a max of 75 bytes,
and folded (continued) lines start with a space. The maximum length can (optionally) be overridden
by specifying $max_len.

Returns the lines of adjusted text in an array ref.

=cut

sub fold_string {
    my ( $str, $max_len ) = @_;
    logfunc();
    utf8::decode($str);
    dbg("=[fold_string]= : str = {[$str]}");
    return [] if !length $str;
    my @chunks;
    $max_len //= '75';
    $str =~ s/\s+/ /g;

    #     dbg("=[fold_string]= : str is currently ($str)");
    while ( length($str) > $max_len ) {
        my $chunk = substr( $str, 0, $max_len, '' );
        utf8::encode($chunk);
        push( @chunks, $chunk );
        $str = ' ' . $str;

        #         dbg("=[fold_string]= : chunk is ($chunk) , str is ($str)");
    }
    if ( length($str) ) {    # Add any remainder
        utf8::encode($str);
        push( @chunks, $str );
    }
    return ( \@chunks );
}

sub _modify_event {    ##no critic(Subroutines::ProhibitManyArgs)
    my ( $self, $action, $action_type, $request, $path, $data_path, $post_dispo_filename, $post_file_type, $total_bytes, $managed_id ) = @_;
    logfunc();
    dbg("=[_modify_event]= : $action,$action_type,$path,$data_path,$post_dispo_filename,$post_file_type,$total_bytes,$managed_id");
    if ( $action eq 'add' ) {
        if ( $action_type eq 'attachment' ) {

            dbg("=[_modify_event]= :  getting stat of $data_path");
            $data_path =~ s/\%40/\@/;

            my $req_path = $request->uri->path;
            dbg("=[_modify_event]= : req_path is $req_path, post_dispo_filename is $post_dispo_filename ");
            my $url = 'https://' . $request->{'_headers'}{'host'} . Cpanel::Encoder::URI::uri_encode_dirstr( $self->{'request_info'}{'uri_decoded_safe'} . '-attachment-' . $managed_id . '-' . MIME::Base64::encode_base64( $post_dispo_filename, '' ) );

            #             my $url = 'https://10.2.71.49:2080'. Cpanel::Encoder::URI::uri_encode_dirstr('/principals/' . $self->{'auth_user'} . $req_path .'-attachment-'. $managed_id .'-'. MIME::Base64::encode_base64($post_dispo_filename,''));
            dbg("=[_modify_event]= : URL($url)");
            my $attach_line = "ATTACH;FILENAME=$post_dispo_filename;FMTTYPE=$post_file_type;SIZE=$total_bytes;MANAGED-ID=$managed_id:$url";

            # Ensure we fold the attach line at 74 bytes to ensure we are under the suggested 75
            my $chunks_hr = fold_string( $attach_line, 74 );
            $attach_line = join( "\r\n", @{$chunks_hr} ) . "\r\n";
            dbg("=[_modify_event]= : ATTACH LINE after folding:\n$attach_line");

            # Read in the existing file, then splice in the attach line, write it all back out
            if ( open( my $dav_fh, '<', $path ) ) {
                my @dav_lines = (<$dav_fh>);
                close($dav_fh);
                my $index = 0;
                $index++ until $dav_lines[$index] =~ m/^BEGIN\:(VEVENT|VCARD)/;
                splice( @dav_lines, $index + 1, 0, $attach_line );

                # Write it back out
                my $tmp_path   = "$path.$$.tmp";
                my $orig_umask = umask(0077);
                if ( open( my $dav_out_fh, '>', $tmp_path ) ) {
                    foreach my $line (@dav_lines) {
                        print $dav_out_fh $line;
                    }
                    close($dav_out_fh);
                    if ( _rename( $tmp_path, $path ) ) {
                        dbg("=[_modify_event]= :  wrote modified file to ([$path])");
                    }
                    else {
                        dbg("=[_modify_event]= :  Could not rename ([$tmp_path]) to ([$path]) : $!");
                    }
                }
                else {
                    dbg("=[_modify_event]= :  could not open ([$path]) via ([$tmp_path]) for writing : $!");
                }
                umask($orig_umask);
            }
            else {
                dbg("=[_modify_event]= :  can not read from ([$path]) : $!");
            }
            dbg("=[_modify_event]= : returning managed_id : $managed_id");
            return 1;
        }
        else {
            dbg("=[_modify_event]= :  : Unknown action_type: $action_type");
        }
    }
    else {
        dbg("=[_modify_event]= :  : Unknown action: $action");
    }
    return 0;
}

=head2 get_upload_limit()

Get the upload limit in bytes for cpdavd requests. This corresponds to C<cpdavd_caldav_upload_limit> in Tweak Settings.

=cut

# Custom config for getting user-set upload limit can go here
sub get_upload_limit {
    my $upload_limit_bytes = 10485760;    # 10MB in bytes. If this default is changed, update the text in whostmgr/docroot/themes/x/tweaksettings/Main.yaml
    logfunc();
    require Cpanel::Config::LoadCpConf::Micro;
    my $config_value = Cpanel::Config::LoadCpConf::Micro::loadcpconf()->{'cpdavd_caldav_upload_limit'};
    if ( length $config_value ) {
        $config_value = $config_value * 1048576;    # Value in cpanel.config is in MB, so we just expand that here for bytes
        dbg("get_upload_limit: got upload limit of $config_value from cpconf, considering that instead of default $upload_limit_bytes");
    }

    # Make sure we got a number, if it's 0 or less, just use the default
    if ( $config_value =~ m/^\d+$/ && $config_value > 0 ) {
        dbg("get_upload_limit: returning $config_value");
        return $config_value;
    }
    dbg("get_upload_limit: returning $upload_limit_bytes");
    return $upload_limit_bytes;
}

=head2 check_if_over_upload_limit($response, $bytes)

Pass in an HTTP::Response object ($reponse) and the number of bytes ($bytes) that were included in the upload request.

If over the limit, the response object will be updated with an appropriate status.

Returns 1 if over; 0 otherwise.

=cut

sub check_if_over_upload_limit {
    my ( $self, $response, $bytes ) = @_;
    logfunc();
    my $upload_limit_bytes = $self->get_upload_limit();    # Use disk math for 2MB in bytes
    if ( $bytes > $upload_limit_bytes ) {
        dbg("check_against_upload_limit: number of bytes ($bytes) being uploaded is greater than our limit, $upload_limit_bytes, sending 413 response.");
        $response->code(413);
        $response->message("Payload Too Large");
        return 1;
    }
    return 0;
}

=head2 save_freebusy_data()

B<Not an instance method.>

Given the .freebusy.json file path $fb_full_path, the system username $user, and the data to save $fb_data_hr, save the updated free/busy information.

=cut

sub save_freebusy_data {
    my ( $fb_full_path, $user, $fb_data_hr ) = @_;
    logfunc();

    # Add a version field right before writing, so as not to confuse the if( keys %fb_data ) check around the caller
    $fb_data_hr->{'__cp_fb_vers'} = 1;
    my $msg = '';
    require Cpanel::JSON;
    require Cpanel::SafeFile;
    my $fb_json   = Cpanel::JSON::Dump($fb_data_hr);
    my $privs_obj = Cpanel::DAV::CaldavCarddav::_drop_privs_if_needed($user);
    my $filelock  = Cpanel::SafeFile::safeopen( my $fb_fh, '>', $fb_full_path );

    if ( !$filelock ) {
        $msg = "Could not get lock and open $fb_full_path for writing : $!";
    }
    else {
        print $fb_fh $fb_json;
        Cpanel::SafeFile::safeclose( $fb_fh, $filelock );
        $msg = "Saved json for Free-Busy data to $fb_full_path";
    }
    my @caller = caller();
    if ( $caller[0] eq 'Cpanel::DAV::CaldavCarddav' ) {    # This lets scripts calling from outside of this module not get caught up in needing a dbg() handler
        dbg("([save_freebusy_data]) : $msg");
    }
    else {
        print "$msg \n";
    }
    return;
}

=head2 remove_freebusy_data($fb_full_path, $user, $fb_newdata_hr)

B<Not an instance method.>

Delete free/busy data for the specified path $fb_full_path. $user is the system user.

If $fb_newdata_hr has a uid, delete the uid. If it does not, the assumed intention is to delete the entire collection from the fb data.
While rebuilding the fb data is easy, it's manual, so take care here.

=cut

sub remove_freebusy_data {
    my ( $fb_full_path, $user, $fb_newdata_hr ) = @_;
    logfunc();

    # At some point we *might* be dealing with a translation from 'ye olde' version of this file to a newer one, but for now that remains unknown
    # Load existing data
    dbg("=[remove_freebusy_data]= : loading db data from $fb_full_path");
    my $fb_data_hr = load_freebusy_data($fb_full_path);

    # Merge updated chunk into existing
    foreach my $collection ( keys %{$fb_newdata_hr} ) {
        dbg("=[remove_freebusy_data]= : in collection $collection");
        my $found_uid_in_collection = 0;
        foreach my $uid ( keys %{ $fb_newdata_hr->{$collection} } ) {
            $found_uid_in_collection++;
            dbg("=[remove_freebusy_data]= : Removing UID $uid from collection $collection");
            delete $fb_data_hr->{$collection}{$uid};
        }
        if ( !$found_uid_in_collection ) {
            dbg("=[remove_freebusy_data]= : No UID in collection, so removing entire collection");
            delete $fb_data_hr->{$collection};
        }
    }

    # Save the modified version
    save_freebusy_data( $fb_full_path, $user, $fb_data_hr );
    return;
}

=head2 remove_freebusy_data($fb_full_path, $user, $fb_newdata_hr)

B<Not an instance method.>

Modify free/busy data for the specified path $fb_full_path without (necessarily) replacing existing fields. $user is the system user.

=cut

sub modify_freebusy_data {
    my ( $fb_full_path, $user, $fb_newdata_hr ) = @_;
    logfunc();

    # At some point we *might* be dealing with a translation from 'ye olde' version of this file to a newer one, but for now that remains unknown
    # Load existing data
    my $fb_data_hr = load_freebusy_data($fb_full_path);

    # Merge updated chunk into existing
    foreach my $collection ( keys %{$fb_newdata_hr} ) {
        foreach my $uid ( keys %{ $fb_newdata_hr->{$collection} } ) {
            $fb_data_hr->{$collection}{$uid} = $fb_newdata_hr->{$collection}{$uid};
        }
    }

    # Save the modified version
    save_freebusy_data( $fb_full_path, $user, $fb_data_hr );
    return;
}

=head2 load_freebusy_data($fb_full_path)

B<Not an instance method.>

Load the .freebusy.json file corresponding to the path specified in $fb_full_path.

=cut

# When loading the .freebusy.json file, be sure to get the version out of the hash before using the data, something like
# my $file_version = delete $fb_data_hr->{'__cp_fb_vers'};

sub load_freebusy_data {
    my ($fb_full_path) = @_;
    logfunc();
    if ( !-f $fb_full_path || $fb_full_path !~ m/\.freebusy\.json$/ ) {
        dbg("([load_fb_data]) : no such file $fb_full_path");
        return {};
    }
    require Cpanel::JSON;
    my $fb_data_hr   = Cpanel::JSON::LoadFile($fb_full_path);
    my $file_version = delete $fb_data_hr->{'__cp_fb_vers'};
    my $msg          = '';
    if ( $file_version =~ m/^\d+/ ) {
        $msg = "File Version : $file_version";
        return $fb_data_hr;
    }
    else {
        $msg = "Data seems bad?";
        return undef;
    }
    my @caller = caller();
    if ( $caller[0] eq 'Cpanel::DAV::CaldavCarddav' ) {    # This lets scripts calling from outside of this module not get caught up in needing a dbg() handler
        dbg("([load_freebusy_data]) : $msg");
    }
    else {
        print "$msg \n";
    }

    return;
}

=head2 clean_attachments_from_raw_ics($ics_path, $raw_ics_data_ref)

Given a path on disk ($ics_path) to an ics file and the ics data itself as a scalar ref ($raw_ics_data_ref), compare the
attachments referenced in the ics data against the attachments on disk corresponding to this event, and remove any on disk
that aren't referenced in the ics data.

=cut

sub clean_attachments_from_raw_ics {
    my ( $self, $ics_path, $raw_ics_data_ref ) = @_;
    logfunc();
    dbg( "_[clean_attachments_from_raw_ics]_ : need to find all attachments in this and remove any on disk that don't match $ics_path :\n$raw_ics_data_ref", $self );
    my $original_ics_parsed_hr;
    eval { $original_ics_parsed_hr = Text::VCardFast::vcard2hash( ${$raw_ics_data_ref} ); };
    if ($@) {
        dbg( "_[clean_attachments_from_raw_ics]_ : Failed to parse VCARD: ", $@, $raw_ics_data_ref );
        return;
    }

    # dbg("_[clean_attachments_from_raw_ics]_ : parsed : ", $original_ics_parsed_hr );
    # find attachments matching the ics name
    my @path_parts   = split( '/', $ics_path );
    my $ics_filename = pop(@path_parts);
    my $col_dir      = join( '/', @path_parts );

    # We limit the files that can be unlinked to the collection the .ics is in, matching $ics_filename-attachment-*
    my @attachments_on_disk;
    if ( opendir( my $dir_fh, $col_dir ) ) {
        while ( my $file = readdir($dir_fh) ) {
            if ( $file =~ m/^\Q$ics_filename\E\-attachment\-+/ ) {
                push( @attachments_on_disk, $file );
            }
        }
        closedir($dir_fh);
    }
    dbg( "_[clean_attachments_from_raw_ics]_ : $col_dir and $ics_filename ", \@attachments_on_disk );

    # find attachments referenced in the ics
    my $attachments_in_ics_ar = $self->find_key_and_collect_matches( $original_ics_parsed_hr, 'attach' );
    my @attachments_in_ics;
    foreach my $entries_ar ( @{$attachments_in_ics_ar}[0] ) {
        foreach my $attachment_entry ( @{$entries_ar} ) {
            dbg( "_[clean_attachments_from_raw_ics]_ : attach: ", $attachment_entry );
            my $attachment_url = $attachment_entry->{'value'};
            dbg("_[clean_attachments_from_raw_ics]_ : url is $attachment_url");
            my @attachment_url_parts = split( '/', $attachment_url );
            push( @attachments_in_ics, $attachment_url_parts[-1] );
        }
    }
    dbg( "_[clean_attachments_from_raw_ics]_ : attachments in ics: ", \@attachments_in_ics );

    # unlink any attachments on the filesystem that aren't present in the ics
    foreach my $attachment_on_disk (@attachments_on_disk) {

        # attachments paths are url encoded in the ics, but not on disk, so we want to be sure those match. We use the same encoder here that is used when creating the attach line
        if ( !grep { $_ eq Cpanel::Encoder::URI::uri_encode_dirstr($attachment_on_disk) } @attachments_in_ics ) {
            dbg("_[clean_attachments_from_raw_ics]_ : $attachment_on_disk is on the fs, but was not found in the ics, removing $col_dir/$attachment_on_disk");
            unlink $col_dir . '/' . $attachment_on_disk;
        }
    }
    return;
}

=head2 get_freebusy_data_from_parsed_ics($events_info_ar)

B<Not an instance method.>

Given an array ref ($events_info_ar) of parsed calendar events, return the free/busy data corresponding to those events:
A hash ref of event uids mapped to 'dtstart'/'dtend' values or 'allday' for all-day events.

=cut

sub get_freebusy_data_from_parsed_ics {
    my ($events_info_ar) = @_;
    logfunc();

    #     dbg("_[get_freebusy_data_from_parsed_ics]_ : arg is: ", $events_info_ar);
    my %fb_data;
    my $uid;
    require DateTime::Format::Strptime;
    foreach my $event_ar ( @{$events_info_ar} ) {
        if ( !defined $event_ar->{'dtstart'} ) {

            # So far all of these are VTODOs and will result in $event_ar being empty since get_events_info only parses data from VEVENTs
            dbg("_[get_freebusy_data_from_parsed_ics]_ : Event is missing DTSTART");
            next;
        }

        # If the event has a dtstart but not dtend, see if it is an allday event. If so, add 24 hours, otherwise we consider it a bad event and ignore it.
        if ( !defined $event_ar->{'dtend'} ) {

            # Check the dtstart string and see if it's just a date, rather than date-time, which indicates it's an all-day event
            # Due to the lack of time/timezone, allday events are considered to be from midnight to midnight, UTC.
            # For now we just check for 8 digits and hope people aren't planning events for 9999-99-99
            # Checking for less than 99999999 on an 8 digit number only serves to ensure if we +1 it, it doens't become a 9 digit number.
            # If needed we can expand the regex to something like ^\d{4}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])$ to try to enforce more reasonable months and days, but.. meh.
            if ( $event_ar->{'dtstart'}{'value'} =~ m/^\d{8}$/ && $event_ar->{'dtstart'}{'value'} < 99999999 ) {
                $event_ar->{'dtend'}{'value'} = $event_ar->{'dtstart'}{'value'} + 1;    # Add a day to DTSTART and set it as dtend
            }
        }

        $uid = $event_ar->{'uid'}->{'value'};

        # Check for all-day events based on dtstart. If it's in YYYYMMDD format, consider it all-day from midnight of the given date + 24hrs
        if ( length $event_ar->{'dtstart'}{'value'} && $event_ar->{'dtstart'}{'value'} =~ m/^\d{8}$/ && $event_ar->{'dtstart'}{'value'} < 99999999 ) {
            $event_ar->{'dtstart'}{'value'} .= 'T000000Z';      # The Z and setting UTC are equiv, but it doesn't hurt.
            $event_ar->{'dtstart'}{'params'}{'tzid'} = 'UTC';
            $fb_data{$uid}{'allday'}                 = 1;       # indicating that this is an allday event may prove to be useful in FB info at some point, to indicate
                                                                # it is more than just a midnight-midnight event
        }

        # dtend exists at this point, whether provided from client or we just added it in the block above due to dtstart matching the allday format.
        # Either way, if it matches the allday format, it will be midnight UTC, so we can just convert it as such and still use a single date-time parser format
        # DTSTART;VALUE=DATE:20231020
        # DTEND;VALUE=DATE:20231021

        if ( length $event_ar->{'dtend'}{'value'} && $event_ar->{'dtend'}{'value'} =~ m/^\d{8}$/ && $event_ar->{'dtend'}{'value'} < 99999999 ) {
            $event_ar->{'dtend'}{'value'} .= 'T000000Z';
            $event_ar->{'dtend'}{'params'}{'tzid'} = 'UTC';
        }

        dbg("_[get_freebusy_data_from_parsed_ics]_ : about to call Striptime on $event_ar->{'dtstart'}{'params'}{'tzid'}");
        $event_ar->{'dtstart'}{'params'}{'tzid'} = _fix_tzid_if_needed( $event_ar->{'dtstart'}{'params'}{'tzid'} );
        dbg("_[get_freebusy_data_from_parsed_ics]_ : after win32 fix, $event_ar->{'dtstart'}{'params'}{'tzid'}");

        # Get the dtstart and dtend along with the timezones, convert to UTC, then use the UTC value in our FB data
        my $strptime = DateTime::Format::Strptime->new(

            # could there be other patterns found in these, like '%Y-%m-%dT%H:%M:%S' ?
            pattern   => '%Y%m%dT%H%M%S',
            time_zone => $event_ar->{'dtstart'}{'params'}{'tzid'}
        );

        if ( !length $event_ar->{'dtstart'}{'value'} || !length $event_ar->{'dtend'}{'value'} ) {
            dbg("_[get_freebusy_data_from_parsed_ics]_ : Could not parse the DTSTART or DTEND time in the event");
            next;
        }
        my $dtstart = $strptime->parse_datetime( $event_ar->{'dtstart'}{'value'} );
        my $dtend   = $strptime->parse_datetime( $event_ar->{'dtend'}{'value'} );
        if ( !defined $dtstart || !defined $dtend ) {
            dbg("_[get_freebusy_data_from_parsed_ics]_ : Could not parse the DTSTART or DTEND time in the event");
            next;
        }
        $dtstart->set_time_zone('UTC');
        $dtend->set_time_zone('UTC');

        #         my $dtstart_utc = $dtstart->strftime('%Y-%m-%dT%H:%M:%SZ');
        #         my $dtend_utc   = $dtend->strftime('%Y-%m-%dT%H:%M:%SZ');
        # Format DateTime objects as "20231026T203000Z"
        my $dtstart_utc = $dtstart->strftime('%Y%m%dT%H%M00Z');
        my $dtend_utc   = $dtend->strftime('%Y%m%dT%H%M00Z');
        $fb_data{$uid}{'dtstart'} = $dtstart_utc;
        $fb_data{$uid}{'dtend'}   = $dtend_utc;
        if ( defined $event_ar->{'rrule'} ) {
            foreach my $rrule ( @{ $event_ar->{'rrule'} } ) {
                push( @{ $fb_data{$uid}{'rrules'} }, $rrule->{'value'} );
            }
        }
    }
    return \%fb_data;
}

sub _fix_tzid_if_needed {
    my ($tzid) = @_;
    logfunc();
    dbg("_[_fix_tzid_if_needed]_ : tzid is -[$tzid]-");
    require Cpanel::DAV::WinTZ;
    my $newtz = Cpanel::DAV::WinTZ::get_std_tz($tzid);
    dbg("_[_fix_tzid_if_needed]_ : get_std_tz returned -[$newtz]-");
    if ( length $newtz ) {
        return $newtz;
    }
    else {
        return $tzid;
    }
}

# In an effort to cut down on storage, we create a link to the original .ics, and provide a mechanism by which attendees can update their own data within, such as accepted/declined, alarms, etc.
sub _schedule_event_locally {
    my ( $self, $dest_principal, $raw_ics_data_ref ) = @_;
    logfunc();
    dbg( "_[_schedule_event_locally]_ : self, dest princ : -[$dest_principal]- , rawics : ", $self, $$raw_ics_data_ref );
    my $original_path  = $self->{'request_info'}{'fs_root'};
    my @path_parts     = split( '/', $self->{'request_info'}{'fs_root'} );
    my $filename       = $path_parts[-1];
    my $symlinked_path = $self->{'acct_homedir'} . '/.caldav/' . $dest_principal . '/calendar/' . $filename;

    # Create a symlink to the original, visible in the user's default calendar (what we use for schedule-inbox-URL)
    dbg("_[_schedule_event_locally]_ : original copy of ics is ([$original_path]), making link from ([$symlinked_path])");

    # If the symlink already exists, and the user is replying to an invite, we only allow them to change their PARTSTAT in their respective ATTENDEE line and possibly bump the SEQUENCE.
    # Anything else is ignored. Once we have isolated their PARTSTAT change, we open the link and modify just that part in the original.
    if ( -l $symlinked_path ) {
        my $err_code = $self->_update_partstat_for_attendee( $dest_principal, $symlinked_path, $raw_ics_data_ref );
        if ($err_code) {
            return $err_code;
        }

    }
    elsif ( !symlink( $original_path, $symlinked_path ) ) {
        dbg("_[_schedule_event_locally]_ : ![failed to create symlink for invite:]! $!");
        return;
    }
    return;
}

=head2 get_current_dtstamp()

B<Not an instance method.>

Return a timestamp of the current time, suitable for use in DTSTAMP-style fields in ics data.

=cut

sub get_current_dtstamp {
    my ( $sec, $min, $hour, $mday, $mon, $year ) = _gmtime();
    $year += 1900;
    $mon  += 1;
    my $dtstamp = sprintf( '%04d%02d%02dT%02d%02d%02dZ', $year, $mon, $mday, $hour, $min, $sec );
    return $dtstamp;
}

sub _gmtime {
    return gmtime();
}

=head2 get_epooch_from_dtstamp($dstamp)

B<Not an instance method>

Given a timestamp in DTSTAMP style, return the number of seconds since the Unix epoch, corresponding to that time.

=cut

sub get_epoch_from_dtstamp {
    my ($dtstamp) = @_;
    require DateTime;
    require DateTime::Format::Strptime;
    my $parser = DateTime::Format::Strptime->new(
        pattern   => '%Y%m%dT%H%M%SZ',
        time_zone => 'UTC',
    );
    my $dt = $parser->parse_datetime($dtstamp);
    return $dt->epoch();
}

# This was written with the common use case of a single VEVENT per .ics file. If we run into a situation where there are multiple VEVENTs, we'll need to expand this
sub _update_partstat_for_attendee {    ##no critic(Subroutines::ProhibitExcessComplexity)
    my ( $self, $dest_principal, $symlinked_path, $raw_ics_data_ref ) = @_;
    logfunc();
    dbg("_[_update_partstat_for_attendee]_ : Updating ([$symlinked_path]) for -[$dest_principal]- based on the data in \$raw_ics_data_ref");

    # Take the "updated" ics data submitted by the client and build a hash of the attendees and their related paramters
    my $sequence = 0;
    my $dtstamp;
    my $class;
    my $new_partstat;
    my %attendees_update_hash;
    my @new_symlinks;

    if ( !defined $$raw_ics_data_ref || !length $$raw_ics_data_ref ) {
        dbg("_[_update_partstat_for_attendee]_ : \$raw_ics_data_ref was empty, so just returning");    # Seen in unit test runs
        return;
    }

    my $unfolded_ics_sr = $self->_unfold_raw_ics_data($raw_ics_data_ref);

    foreach my $line ( split( /[\r\n]+/, $$unfolded_ics_sr ) ) {

        # Build a hash of the new/updated attendees, so we can use that to properly modify %attendees_hash below. We need to know about
        # all the attendees, not just the $dest_principal
        if ( $line =~ m/^ATTENDEE;(.+?):(.+)$/i ) {
            my $params   = $1;
            my $attendee = $2;
            $attendee =~ s/^mailto\://ig;
            dbg("_[_update_partstat_for_attendee]_ : found attendee in submitted event -[$attendee]-");
            my $cnt = my @params_array = split( ';', $params );
            dbg("_[_update_partstat_for_attendee]_ : params array = @params_array");
            my $found_partstat = 0;

            for my $i ( 0 .. $#params_array ) {
                my ( $key, $value ) = split( '=', $params_array[$i] );
                $attendees_update_hash{$attendee}{ uc($key) } = $value;
            }
            dbg( "_[_update_partstat_for_attendee]_ : attendees_update_hash before assigning params: ", \%attendees_update_hash );

            # Should be OK to force this as a default ?
            if ( !defined( $attendees_update_hash{$attendee}{'PARTSTAT'} ) ) { $attendees_update_hash{$attendee}{'PARTSTAT'} = 'NEEDS-ACTION'; }
            $new_partstat = $attendees_update_hash{$attendee}{'PARTSTAT'};

        }
        elsif ( $line =~ m/^SEQUENCE:(\d+)$/ ) {
            $sequence = $1;
            dbg("_[_update_partstat_for_attendee]_ : found SEQUENCE : $sequence");

        }
        elsif ( $line =~ m/^DTSTAMP:(\d{8}T\d{6}Z)$/ ) {
            $dtstamp = $1;
            dbg("_[_update_partstat_for_attendee]_ : found DTSTAMP : $dtstamp");

        }
    }

    # This would only happen if the $dest_principal was somehow not an ATTENDEE in the updated/submitted event
    if ( !length( $attendees_update_hash{$dest_principal}{'PARTSTAT'} ) ) {
        dbg("_[_update_partstat_for_attendee]_ : ![Could not find PARTSTAT change in attendee reply for]! ([$symlinked_path])");
        return 3;
    }

    my $event_file_name;
    if ( $symlinked_path =~ m/^(.+\/)(.+\.ics)\.tmp$/ ) {
        dbg("_[_update_partstat_for_attendee]_ : converting a .tmp path to original for modification");

        $event_file_name = $2;
        $symlinked_path  = $1 . $2;
    }
    dbg( sprintf "_[_update_partstat_for_attendee]_ : event_file_name is %s and symlinked_path = %s", $event_file_name // '(undef)', $symlinked_path // '(undef)' );

    # Open the original ics file and update the partstat for the attendee/$dest_principal

    my $orig_ics_fh;
    if ( !open $orig_ics_fh, '<', $symlinked_path ) {
        dbg("_[_update_partstat_for_attendee]_ : ![Could not open]! ([$symlinked_path]) ![for reading :]! $!");
        return 4;    #arbitrary error code
    }
    my $orig_ics;
    while (<$orig_ics_fh>) {
        $orig_ics .= $_;
    }
    close($orig_ics_fh);
    my @updated_orig_ics;
    my $unfolded_orig_ics_sr = $self->_unfold_raw_ics_data( \$orig_ics );
    my $attendee_to_rm;
    my %attendees_hash;

    foreach my $line ( split( /[\r\n]+/, $$unfolded_orig_ics_sr ) ) {
        next if $line =~ m/^\s+$/g;
        next if !length $line;

        if ( $line =~ m/^ATTENDEE;(.+?):(.+)$/i ) {
            my $params   = $1;
            my $attendee = $2;
            $attendee =~ s/^mailto\://ig;
            dbg("_[_update_partstat_for_attendee]_ : found attendee in original event -[$attendee]-");
            my @params_array = split( ';', $params );
            dbg("_[_update_partstat_for_attendee]_ : params array = @params_array");
            my $found_partstat = 0;

            for my $i ( 0 .. $#params_array ) {
                my ( $key, $value ) = split( '=', $params_array[$i] );
                $attendees_hash{$attendee}{ uc($key) } = $value;
            }
            dbg( "_[_update_partstat_for_attendee]_ : attendees_hash before assigning params: ", \%attendees_hash );

            if ( !defined( $attendees_hash{$attendee}{'PARTSTAT'} ) ) { $attendees_hash{$attendee}{'PARTSTAT'} = 'NEEDS-ACTION'; }

            if ( $attendee eq $dest_principal ) {
                dbg("_[_update_partstat_for_attendee]_ : matched $attendee to dest_principal");
                dbg( "_[_update_partstat_for_attendee]_ : existing and new attendee data: ", $attendees_hash{$attendee}, $attendees_update_hash{$attendee} );

                my $method = uc( $self->{'request_info'}{'method'} );
                $attendees_update_hash{$attendee}{'PARTSTAT'} = 'DECLINED' if ( $method eq 'DELETE' );
                dbg( "_[_update_partstat_for_attendee]_ : if deleting, then decline: ", $method );

                # User is delegating their PARTSTAT to another user
                if ( $attendees_hash{$attendee}{'PARTSTAT'} ne 'DELEGATED' and $attendees_update_hash{$attendee}{'PARTSTAT'} eq 'DELEGATED' ) {
                    dbg("_[_update_partstat_for_attendee]_ : this is for our target attendee, -[$attendee]-, and their new PARTSTAT is DELEGATED, but was not before..");
                    $attendees_hash{$attendee}{'PARTSTAT'} = 'DELEGATED';
                    $attendees_hash{$attendee}{'ROLE'}     = 'NON-PARTICIPANT';
                    if ( defined( $attendees_update_hash{$attendee}{'DELEGATED-TO'} ) ) {
                        my $delegated_to = $attendees_update_hash{$attendee}{'DELEGATED-TO'};
                        $attendees_hash{$attendee}{'DELEGATED-TO'} = $delegated_to;

                        # Create a new attendee based on the DELEGATED-TO, if the update includes it
                        if ( !defined( $attendees_hash{$delegated_to} ) ) {

                            # Build line for new $attendee and add it.
                            my $new_del_line = 'ATTENDEE;';
                            $new_del_line .= join ';', map { "$_=$attendees_update_hash{$delegated_to}{$_}" } keys %{ $attendees_update_hash{$delegated_to} };
                            $new_del_line .= ':mailto:' . $delegated_to;
                            push( @updated_orig_ics, $new_del_line );

                            # Create symlink for this attendee too. We do this by adding the destination to an array and processing them later, after the modification to the original
                            # event has completed successfully. In the event permission was ultimately denied, we don't have to undo this link.
                            push( @new_symlinks, $self->{'acct_homedir'} . '/.caldav/' . $delegated_to . '/calendar/' . $event_file_name ) if -d $self->{'acct_homedir'} . '/.caldav/' . $delegated_to . '/calendar/';

                        }
                    }

                    # When an attendee has previously delegated their participation but changes their mind, we need to "uninvite" the previously delegated-to user and remove their event file link
                }
                elsif ( $attendees_hash{$attendee}{'PARTSTAT'} eq 'DELEGATED' and $attendees_update_hash{$attendee}{'PARTSTAT'} ne 'DELEGATED' ) {
                    dbg("_[_update_partstat_for_attendee]_ : -[$attendee]- previously delegated their role, but have changed their minds; potentially removing delegated-to user");
                    dbg( "_[_update_partstat_for_attendee]_ : hummmmm", \%attendees_hash, \%attendees_update_hash );
                    my $prev_delegated_to = $attendees_hash{$attendee}{'DELEGATED-TO'};
                    if ( defined $attendees_hash{$prev_delegated_to}{'DELEGATED-FROM'} && $attendees_hash{$prev_delegated_to}{'DELEGATED-FROM'} eq $attendee ) {
                        dbg("_[_update_partstat_for_attendee]_ : Removing previously delegated user, -[$prev_delegated_to]-");

                        #                         delete $attendees_update_hash{$prev_delegated_to};
                        #                         delete $attendees_hash{$prev_delegated_to};
                        $attendee_to_rm = $prev_delegated_to;
                    }
                    $attendees_hash{$attendee} = $attendees_update_hash{$attendee};

                    # Proceed to update the attendee with their new status, no special processing needed
                }
                else {
                    $attendees_hash{$attendee} = $attendees_update_hash{$attendee};
                }

            }
            else {
                dbg("_[_update_partstat_for_attendee]_ : Ignoring non-target attendee -[$attendee]-");
            }

            dbg( "_[_update_partstat_for_attendee]_ : attendees_hash after assigning params: ", \%attendees_hash );

            # Build line for current $attendee and add it.
            my $new_attendee_line = 'ATTENDEE;';
            $new_attendee_line .= join ';', map { "$_=$attendees_hash{$attendee}{$_}" } keys %{ $attendees_hash{$attendee} };
            $new_attendee_line .= ':mailto:' . $attendee;
            push( @updated_orig_ics, $new_attendee_line );

        }
        elsif ( $line =~ m/^SEQUENCE:(\d+)$/ ) {
            my $orig_sequence = $1;
            dbg("_[_update_partstat_for_attendee]_ : original SEQUENCE = $orig_sequence , updated one from attendee is $sequence");

            # If orig is higher than new, ignore new, otherwise, bump it
            if ( $orig_sequence < $sequence ) {
                push( @updated_orig_ics, 'SEQUENCE:' . $sequence );
            }
        }
        elsif ( $line =~ m/^DTSTAMP:(\d{8}T\d{6}Z)$/ ) {
            my $orig_dtstamp = $1;
            dbg("_[_update_partstat_for_attendee]_ : original DTSTAMP : $orig_dtstamp , updated one from attendee is $dtstamp");
            my $orig_epoch     = get_epoch_from_dtstamp($orig_dtstamp);
            my $attendee_epoch = get_epoch_from_dtstamp($dtstamp);
            if ( length $attendee_epoch != 10 ) {

                # Use existing DTSTAMP
                dbg("_[_update_partstat_for_attendee]_ : DTSTAMP $dtstamp from attendee does not appear to be valid when converted to unix epoch : $attendee_epoch . Ignoring");
                push( @updated_orig_ics, 'DTSTAMP:' . $orig_dtstamp );
                next;
            }
            my $difference          = $attendee_epoch - $orig_epoch;
            my $current_epoch       = time();
            my $difference_from_now = $current_epoch - $attendee_epoch;
            if ( $difference < 0 ) {

                # Use existing DTSTAMP
                dbg("_[_update_partstat_for_attendee]_ : DTSTAMP $dtstamp from attendee is older than original DTSTAMP $orig_dtstamp , ignoring");
                push( @updated_orig_ics, 'DTSTAMP:' . $orig_dtstamp );
            }
            elsif ( $difference_from_now > 300 ) {

                # Use existing DTSTAMP
                dbg("_[_update_partstat_for_attendee]_ : DTSTAMP $dtstamp from attendee is more than 5 minutes in the future, too much time skew, ignoring");
                push( @updated_orig_ics, 'DTSTAMP:' . $orig_dtstamp );
            }
            else {
                # Update the DTSTAMP in the original ICS
                dbg("_[_update_partstat_for_attendee]_ : DTSTAMP getting a shiny new update..");
                push( @updated_orig_ics, 'DTSTAMP:' . $dtstamp );
            }
        }
        elsif ( $line =~ m/^CLASS:(.+)$/ ) {
            $class = $1;
            dbg("_[_update_partstat_for_attendee]_ : found CLASS : $class");
            push( @updated_orig_ics, $line );
        }
        else {
            push( @updated_orig_ics, $line );
        }
    }

    # If this change is not being made by the organizer, see if it's a shared collection. If the auth_user is neither the organizer or a shared-to user, we assume it
    # is an attendee of an event. In this case, we restrict saving their PARTSTAT as DELEGATED when an event is set to PRIVATE or CONFIDENTIAL.
    my $final_destination = readlink($symlinked_path);    # this function is always given a symlink
    dbg("_[_update_partstat_for_attendee]_ : original file is at ([$final_destination]) (read link from ([$symlinked_path]))");

    # If the attendee/dest_principal does not own this collection and the event classification was private/confidential, we don't allow attendees to delegate their participation
    my $path_info_hr = $self->_parse_request_path($final_destination);
    if ( length $path_info_hr->{'principal_user'} && $path_info_hr->{'principal_user'} ne $self->{'auth_user'} ) {
        if ( length($class) ) {
            dbg("_[_update_partstat_for_attendee]_ : class = $class and new_partstat = $new_partstat");
            if ( $class =~ m/private|confidential/i and $new_partstat =~ m/^delegated$/i ) {
                dbg("_[_update_partstat_for_attendee]_ : Event was marked as $class and attendee attemptted to delegate the meeting, returning error.");
                return 5;    # arbitrary code we can use by the caller to throw the error to the client
            }
        }
    }
    else {
        dbg( "_[_update_partstat_for_attendee]_ : original event file ([$final_destination]) owned by currently authenticated user =[" . $self->{'auth_user'} . "]=, skipping CLASS check" );
    }

    # If we need to remove an un-delegated attendee, splice it out of the final array and remove their symlink path for the event.
    if ( length $attendee_to_rm ) {
        for my $i ( 0 .. $#updated_orig_ics ) {
            if ( $updated_orig_ics[$i] =~ m/^ATTENDEE.+\:\Q$attendee_to_rm\E$/ ) {
                dbg("_[_update_partstat_for_attendee]_ : Removing un-delegated attendee -[$attendee_to_rm]- from event");
                splice( @updated_orig_ics, $i, 1 );
                last;
            }
        }
        my $rm_sym_path = $self->{'acct_homedir'} . '/.caldav/' . $attendee_to_rm . '/calendar/' . $event_file_name;
        if ( -l $rm_sym_path ) {
            dbg("_[_update_partstat_for_attendee]_ : removing symlink at $rm_sym_path");
            unlink $rm_sym_path;
        }
    }

    ########################################################################
    # Fold our strings and write them to the file
    ########################################################################
    dbg( "_[_update_partstat_for_attendee]_ : going to save the following to $symlinked_path :\n", \@updated_orig_ics );
    if ( !open $orig_ics_fh, '>', $symlinked_path ) {
        dbg("_[_update_partstat_for_attendee]_ : ![Could not open]! ([$symlinked_path]) ![for writing :]! $!");
        return 7;
    }
    foreach my $line (@updated_orig_ics) {
        foreach ( @{ fold_string($line) } ) {
            if ( length $_ ) {
                print $orig_ics_fh "$_\n";
            }
        }
    }
    close($orig_ics_fh);

    # Create any new symlinks for delegated-to users
    foreach my $target (@new_symlinks) {
        dbg("-[_update_partstat_for_attendee]- : linking ([$final_destination]) to new target, ([$target])");
        if ( -e $target ) {
            dbg("-[_update_partstat_for_attendee]- : ([$target]) already exists");
        }
        else {
            if ( !symlink( $final_destination, $target ) ) {
                dbg("-[_update_partstat_for_attendee]- : Failed to create symlink to ([$target]) : $!");
            }
        }
    }

    # Update the mtime on the default calendar collection dir for each attendee
    foreach my $attendee ( keys %attendees_update_hash ) {
        my $attendee_default_caldav_collection_dir = $self->{'acct_homedir'} . '/.caldav/' . $attendee . '/calendar';
        if ( !-d $attendee_default_caldav_collection_dir ) {
            dbg("-[_update_partstat_for_attendee]- : ([$attendee_default_caldav_collection_dir]) is not a directory ?");
            next;
        }
        dbg("-[_update_partstat_for_attendee]- : Updating mtime on $attendee_default_caldav_collection_dir due to event update");
        utime( undef, undef, $attendee_default_caldav_collection_dir );
    }

    return;
}

# Give it a reference to a scalar with a raw vcard data and it will unfold all the lines and return a reference to a scalar without the folding
sub _unfold_raw_ics_data {
    my ( $self, $raw_ics_data_ref ) = @_;
    logfunc();
    my $unfolded = $$raw_ics_data_ref =~ s/\r?\n\s+//mgr;
    return \$unfolded;
}

sub _put {    ## no critic qw(ProhibitExcessComplexity)
    my ( $self, $request, $response, $c ) = @_;
    logfunc();
    my $path = $self->{'request_info'}{'fs_root'};
    dbg( "_[_put]_ : path = ([$path])", $self );
    my $content = $request->content();

    # Add some limitations on what we accept for files. So far the only files I've seen area .ics and .vcf, so deny by default seems like the way to go for now.
    if ( $path !~ m/(\.ics|\.vcf)$/i ) {
        dbg("_[_put]_ : ![PUT request disallowed due to file extension (not .vcf or .ics)]!");
        $response->code(415);    # I really don't know which code best fits here. Lowkey want to 418 it.
        $response->message("PUT not allowed for files which are not vCard or iCalendar format");
        return;
    }

    #     dbg( "PUT content is ", $content ); # This can dump binary output to the log, so only use it when not doing that
    dbg( "_[_put]_ : URI path and self: " . scalar( $request->uri->path ), $self );
    if ( $self->check_write_access( scalar($path) ) ) {
        dbg( "_[_put]_ : we have write access to " . $path );

        # Check size offered by the client against our limit. Even if they fake it and send more data, we only read up to what is claimed, so it will truncate their file.
        my $contentlength = $request->header("Content-Length");
        return if $self->check_if_over_upload_limit( $response, $contentlength );

        # If this is a symlink, it (supposedly) means that the uploader was invited to this event, and are updating their PARTSTAT or something similar,
        # so we make a .tmp copy of it to store what they are uploading it, then remove it afterwards. The exception is if the auth user is a calendar-proxy-write delegate, then
        # we allow full access to the file as if it were the original owner.
        my $is_attendee_update = 0;
        if ( -l $path ) {

            # If the auth user is proxy user granted write access, write directly to path and skip attendee update logic
            my $proxy_config_hr = $self->load_proxy_config_data();
            dbg("_[put]_ : FS target is a symlink, checking proxy config data to see if auth user is a delegate with write access");
            my $principal = $self->{'request_info'}{'principal_user'};
            if ( $proxy_config_hr->{$principal}{ $self->{'auth_user'} } ne 'calendar-proxy-write' ) {
                dbg("_[put]_ : Currently authenticated user $self->{'auth_user'} is granted permission to read from ([$path]) via proxy config");
                $path               = $path . '.tmp';
                $is_attendee_update = 1;
            }
        }
        if ( open my $fh, ">", $path ) {
            dbg("_[_put]_ : created file at ([$path])");
            $response->code(201);
            $response->message("CREATED");

            my $buffer;
            my $original_vcard_data;

            # Only kick in the ics treatment when the content being PUT actually looks like an .ics file
            my $is_ics = 0;
            my $is_vcf = 0;
            if ( $path =~ m/\.ics(\.tmp)?$/i ) {
                $is_ics = 1;
            }
            elsif ( $path =~ m/\.vcf(\.tmp)?$/i ) {
                $is_vcf = 1;
            }

            while ( $contentlength > 0 ) {

                # read a chunk of data into buffer
                my $length = $c->read( $buffer, _min( 1024 * 1024, $contentlength ) );
                dbg("_[_put]_ :  length = $length ($buffer)");
                if ( $length > 0 ) {
                    my $buf_type = ref $buffer;
                    iolog(
                        "\n>>>==[ PUT PAYLOAD TYPE REF: $buf_type ]\n",
                        ">>>==[ PUT PAYLOAD ]=========================================>>>>",
                        $buffer,
                    );
                    print $fh $buffer;
                    $original_vcard_data .= $buffer if $is_ics || $is_vcf;
                    $contentlength -= $length;
                }
                else {
                    select( undef, undef, undef, 0.25 );
                }
            }
            close $fh;

            my @path_stat = stat($path);

            # Verify we have written some data
            if ( $path_stat[7] < 1 ) {
                dbg("_[_put]_ : $path is empty");
                $response->code('400');
                $response->message("Empty file");
                goto QUICKEXIT;
            }
            else {
                dbg( "_[_put]_ : File ([$path]) has size " . $path_stat[7] );
            }

            # Verify .vcf files are legit. .ics files are shaken down later
            if ( $is_ics or $is_vcf ) {
                dbg("_[_put]_ : Seeing if uploaded ics or vcf file is valid");
                my $parsed_vcard_hr;
                eval { $parsed_vcard_hr = Text::VCardFast::vcard2hash($original_vcard_data); };
                if ($@) {
                    dbg( "_[_put]_ : ![Invalid VCARD data in PUT request]!", $original_vcard_data );
                    $response->code('400');
                    $response->message("Invalid VCARD");

                    # unlink $path; # We should probably do this to clean up cruft ? Would need to rework logic in t/small/Cpanel-DAV-CaldavCarddav_invitation.t at least
                    goto QUICKEXIT;
                }
            }

            # Generate an ETag header to help the client with syncing
            $response->header( 'Etag', $self->_get_etag($path) );
            $response->last_modified( $path_stat[9] );

            ##########################################################
            # Do ICS-only things after this point
            ##########################################################
            return if ( !$is_ics && !length $original_vcard_data );

            my @path_parts      = split( '/', $path );
            my $file            = pop @path_parts;
            my $upload_base_dir = join( '/', @path_parts );
            my $collection      = $self->{'request_info'}{'collection'};
            if ( !length $collection ) {
                dbg("_[_put]_ : path ([$path]) does not appear to be part of a collection, but we only allow PUTs inside collections.");
                $response->code(403);
                $response->message("PUT only allowed for collections");
                goto QUICKEXIT;
            }

            # Update the mtime/atime/ctime on the directory to ensure etags based off it reflect changes, even when it's a modification to a symlink target
            # This "touch" happens for all other attendees during _update_partstat_for_attendee(), regardless of which attendee is getting a partstat update.
            dbg("_[_put]_ : updating base dir a/c/mtime ([$upload_base_dir])");
            utime( undef, undef, $upload_base_dir );

            my $events_ar = $self->get_events_info( \$original_vcard_data );

            # If we have no events in the vcard and it's an ics, it's not viable, so we return an error
            if ( $is_ics && @{$events_ar} < 1 ) {
                dbg("_[_put]_ : path ([$path]) does not appear to have any event data in it, returning 400");
                $response->code(400);
                $response->message("Invalid VCARD");
                goto QUICKEXIT;
            }
            dbg( "_[_put]_ : events_ar : ", $events_ar );
            my @attendees = map { $_->{'value'} } @{ $events_ar->[0]->{'attendee'} };
            dbg( "_[_put]_ :  ATTENDEEs: ", \@attendees );

            ##########################################################
            # Update freebusy data
            ##########################################################

            my $fbdata_hr = Cpanel::DAV::CaldavCarddav::get_freebusy_data_from_parsed_ics($events_ar);
            my $fbdata_col_hr;
            $fbdata_col_hr->{$collection} = $fbdata_hr;
            foreach my $uid ( keys %{$fbdata_hr} ) {
                $file =~ s/\.tmp$//;    # Even if this is an attendee response, we still want to record the original ics name in .freebusy.json
                $fbdata_col_hr->{$collection}{$uid}{'file'} = $file;
            }
            dbg( "_[_put]_ : updating freebusy data from $file with :", $fbdata_col_hr );
            dbg( "_[_put]_ : self is :",                                $self );
            my $fb_file_path = $self->{'request_info'}->{'fb_file_path'};
            modify_freebusy_data( $fb_file_path, $self->{'sys_user'}, $fbdata_col_hr );

            # We only permit non-organizer attendees to update their own PARTSTAT and potentially the SEQUENCE
            if ($is_attendee_update) {
                dbg("_[_put]_ : This is being PUT by an attendee, so we will only modify what we need/should");
                $self->_update_partstat_for_attendee( $self->{'auth_user'}, $path, \$original_vcard_data );

                # Update the mtime on all attendee's default calendar so they are aware of the change/get new etag and resync the event
                # HB-7223 - medium - as per https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-sharing.txt #5.5.4, we need to store
                #        TRANSP and VALARM lines in .ics files on a per-user basis, so one person's VALARM does not overwrite any other users' setting.

            }
            else {

                ##########################################################
                # As per https://datatracker.ietf.org/doc/html/rfc8607#section-3.9 , remove any attachments on disk related to event but no longer in the .ics file
                ##########################################################

                $self->clean_attachments_from_raw_ics( $path, \$original_vcard_data );

                ##########################################################
                # Handle sending any invites that are needed
                ##########################################################

                # Keeping this around in case it proves more useful later
                # my $attendees_ar = $self->find_key_and_collect_matches($original_ics_parsed_hr, 'attendee');

                if (@attendees) {
                    dbg("_[_put]_ : sending invites due to presence of attendees");

                    # send the plain text version to the send_invites sub rather than recontructing the parsed version
                    # HB-7224 - large - probably need to revisit this to ensure we aren't sending embedded base64 attachment data or other such junk..
                    #           ** best option is probably to convert to proper ITIP and keep a copy of it somewhere, like *.ics.itip
                    my $err_code = $self->send_invites( \$original_vcard_data, $events_ar, \@attendees ) // -1;
                    if ( $err_code == 5 ) {

                        # Attendee attempted to delegate a private/confidential event
                        $response->code(403);
                        $response->message("Private or Confidential events may not be delegated");
                        return;
                    }
                    elsif ( $err_code == 6 ) {

                        # Attendee attempted to update a resource it did not have access to
                        $response->code(403);
                        $response->message("No permissions to modify event");
                        return;
                    }
                    elsif ( $err_code == 4 ) {

                        # Attendee attempted to update a resource that did not exist
                        $response->code(404);
                        $response->message("Event no longer exists");
                        return;
                    }
                    elsif ( $err_code == 3 ) {

                        # Attendee attempted to update a resource but are not in the attendee list
                        $response->code(403);
                        $response->message("User not found in attendee list for event");
                        return;
                    }
                    elsif ( $err_code == 7 ) {

                        # Attendee attempted to update a resource but are not in the attendee list
                        $response->code(500);
                        $response->message("Server could not save updated event");
                        return;
                    }
                }
            }
        }
        else {
            dbg("_[_put]_ : Can not write to ([$path])");
            $response->code(403);
            $response->message("Insufficient Permissions");
            goto QUICKEXIT;
        }
        if ( $is_attendee_update && $path =~ m/\.tmp$/ ) {
            dbg("_[_put]_ : Removing temp event file ([$path]) since it was PUT by an attendee and processed");
            unlink $path || dbg("_[_put]_ : ![!!! Unable to remove]! ([$path]) ![$!]!");
        }
    }
    else {
        dbg("returning 403 cause check_write_access returned NOPE");
        $response->code(403);
        $response->message("Access Denied");
        goto QUICKEXIT;
    }
    return;
}

=head2 send_invites($original_ics_data_str, $events_ar, $attendees_ar)

Send event invitations to the specified attendees. For remote attendees, this will be done via email.
Local attendees will have their calendar data updated directly to reflect the pending invitation.

=cut

sub send_invites {
    my ( $self, $original_ics_data_sr, $events_ar, $attendees_ar ) = @_;
    logfunc();
    dbg( "_[send_invites]_ : ", $self, $original_ics_data_sr, $events_ar, $attendees_ar );

    my $ev_location    = $events_ar->[0]->{'location'}{'value'};
    my $ev_organizer   = $events_ar->[0]->{'organizer'}{'value'};
    my $ev_description = $events_ar->[0]->{'description'}{'value'};
    my $ev_summary     = $events_ar->[0]->{'summary'}{'value'};
    my $ev_start       = $events_ar->[0]->{'dtstart'}{'value'};
    my $ev_start_tz    = $events_ar->[0]->{'dtstart'}->{'params'}->{'tzid'};
    my $ev_end         = $events_ar->[0]->{'dtend'}{'value'};
    my $ev_end_tz      = $events_ar->[0]->{'dtend'}->{'params'}->{'tzid'};
    my %invite_recipients;
    require Cpanel::Email::Validate;

    # local attendees should be handled locally, while accounts outside the scope of the current system user should get
    # iTIP/iMIP emails. By the time we enter this module we are already running as the user, so expanding local users to include
    # other system accounts is technically challenging, and also a pretty rare scenario.
    #
    # https://datatracker.ietf.org/doc/html/rfc6638#section-3.2.1.1

    # Remove the ORGANIZER from attendees list
    # foreach $attendee( @attendees ) {
    #    if( $self->_user_is_local($attendee) ) {
    #       pass_to_local_invite_handler()
    #    } else {
    #       do_remote_things
    #    }
    # }
    # Set SCHEDULE-AGENT status to SERVER, CLIENT or NONE for local requests, and REQUEST for iTIP/iMIP

    foreach my $attendee ( @{$attendees_ar} ) {
        dbg("_[send_invites]_ : organizer($ev_organizer) walking through attendees.. : $attendee");
        if ( $attendee ne $ev_organizer ) {
            if ( $attendee =~ m/^mailto\:(.+)/ ) {    # helper for common format
                $attendee = $1;
            }
            my $attendee_sysuser;

            # If the $attendee is local to this organizer's system account, use the auto-scheduling mechanisms. Otherwise, send them the email invite.
            my ( $luser, $domain ) = split( /\@/, $attendee );
            if ( !length $domain ) {
                $attendee_sysuser = $luser;
            }
            else {
                $attendee_sysuser = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'default' => undef } );
            }
            dbg("_[send_invites]_ : sysuser for $attendee is $attendee_sysuser");
            if ( $attendee_sysuser eq $self->{'sys_user'} ) {
                dbg("_[send_invites]_ : attendee_sysuser matches org sys_user");
                $invite_recipients{$attendee} = 'l';    # l = local
            }
            else {
                dbg("_[send_invites]_ : attendee_sysuser ($attendee_sysuser) does not match organizer sys_user ($self->{'sys_user'})");
                if ( Cpanel::Email::Validate::valid_email($attendee) ) {
                    $invite_recipients{$attendee} = 'r';    # r = remote
                }
                else {
                    dbg("_[send_invites]_ : ignoring invite to remote attendee $attendee");
                }
            }
        }
    }

    # For local events, skip all the email creation and send the event to the "schedule-inbox-URL" of each rcpt
    foreach my $invitee ( keys %invite_recipients ) {
        if ( $invite_recipients{$invitee} eq 'l' ) {
            dbg("_[send_invites]_ : scheduling locally for $invitee");
            my $err_code = $self->_schedule_event_locally( $invitee, $original_ics_data_sr );
            if ($err_code) {
                return $err_code;
            }
        }
    }

    # Bail out here if we have no remote attendees
    if ( !grep { $_ eq 'r' } values %invite_recipients ) {
        return;
    }

    my @recpients_list = join( ' ', keys %invite_recipients );
    dbg("_[send_invites]_ : Creating and adding our X-CPANEL-ID to the invite ics");
    my $updated_ics_data_sr = $self->insert_invite_data_to_vcard( \$original_ics_data_sr );    # This adds an X-CPANEL-ID line to the vcard which can identify the organizer, collection and event UID
    dbg( "_[send_invites]_ : updated version:",  $$updated_ics_data_sr );
    dbg( "_[send_invites]_ : Sending email to:", \@recpients_list );
    dbg( "_[send_invites]_ : events_ar:",        $events_ar );

    dbg("_[send_invites]_ : START : $ev_start, $ev_start_tz");
    dbg("_[send_invites]_ : END   : $ev_end, $ev_end_tz");

    # Parse our start and end times, then calculate the difference to get the duration
    my $ev_start_info   = $self->simple_date_parser( $ev_start, $ev_start_tz );
    my $ev_end_info     = $self->simple_date_parser( $ev_end,   $ev_end_tz );
    my $ev_duration_obj = $self->get_duration( $ev_start_info, $ev_end_info );

    # Pfft. Just _try_ doing accurate date/time manipulation across all world timezones in Perl without this. Ain't nobody got time for that.
    require DateTime;

    # Get a formatted version of the start time
    my $st_formatted_date = $ev_start_info->strftime('%m/%d/%Y');
    my $st_formatted_time = $ev_start_info->strftime('%l:%M%P %Z');

    #     for my $index (0..@$attendees_ar) {
    #         $$attendees_ar[$index] =~ s/^mailto://;
    #     }

    my $mail_text_data;
    for my $msg (
        [ 'Event starts on %s at %s ', $st_formatted_date, $st_formatted_time ],
        [ 'Location    : %s', $ev_location ],
        [ 'Duration    : %s', $ev_duration_obj->{'string'} ],
        [ 'Organizer   : %s', $ev_organizer ],
        [ 'Attendees   : %s', join( ' ', @recpients_list ) ],
        [ 'Description : %s', $ev_description ],
    ) {
        my $line = sprintf map { $_ // '' } @$msg;
        dbg($line);
        $mail_text_data .= "$line\n";
    }

    require Email::MIME;

    $ev_organizer =~ s/^mailto://;
    if ( !Cpanel::Email::Validate::valid_email($ev_organizer) ) {
        dbg("_[send_invites]_ : ev_organizer ($ev_organizer) was not a valid email, aborting sending of invite");
        return;
    }

    my @parts = (
        Email::MIME->create(
            attributes => {
                content_type => "text/plain",
                disposition  => "attachment",
                charset      => "US-ASCII",
                encoding     => "quoted-printable",
            },
            body_str => $mail_text_data,
        ),
        Email::MIME->create(
            attributes => {
                filename     => "invitation.ics",
                content_type => "text/calendar",
                encoding     => "base64",
                name         => "invitation.ics",
            },
            body => $$updated_ics_data_sr,    # automatically base64 encoded by Email::MIME
        )
    );
    $parts[1]->header_str_set( 'Content-Type' => 'text/calendar; charset="utf-8"; method="request"' );

    # Loop through remote rcpts, as mails with multiple recipients get a much higher spam score on most systems
    foreach my $invitee ( keys %invite_recipients ) {
        if ( $invite_recipients{$invitee} eq 'r' ) {
            my $email = Email::MIME->create(
                header_str => [
                    'From'    => $ev_organizer,           # HB-7225 - small - add support for getting the CN here as well. the parsed organizer should have a CN if available in the ics
                    'To'      => $invitee,
                    'Subject' => "Invite: $ev_summary",
                ],
                'parts' => [@parts],
            );

            #         dbg("Outgoing email will look like:\n", $email->as_string );
            my $ret = $self->send_mail( { 'email' => $email } );
            dbg( "_[send_invites]_ : send_mail returned: ", $ret );
        }
    }
    return;
}

=head2 send_mail($opts_hr)

Send an email specified in C<$opts_hr->{'email'}>.

B<This is currently disabled.> 

=cut

sub send_mail {
    my ( $self, $opts_hr ) = @_;
    logfunc();
    require Email::Sender::Transport::SMTP;
    require Email::Sender::Simple;
    my $smtp_user = $self->{'smtp_user'} // '';
    my $smtp_pass = $self->{'smtp_pass'} // '';
    my $transport = Email::Sender::Transport::SMTP->new(
        {
            'sasl_username' => "__cpanel__service__auth__icontact__$smtp_user",
            'sasl_password' => $smtp_pass,
        }
    );

    return Email::Sender::Simple->try_to_send( $opts_hr->{'email'}, { 'transport' => $transport } );
}

=head2 get_duration($start, $end)

Pass in 2 DateTime objects and get the difference in a hash ref where ->{'string'} provides an easily consumable human readable string.

=cut

sub get_duration {
    my ( $self, $start, $end ) = @_;
    logfunc();
    require DateTime;

    dbg("_[get_duration]_ : start( $start ) and end ( $end )");
    my $duration        = $end->subtract_datetime($start);
    my $duration_string = '';

    # If we ever need expand the scope of the duration to account for events spanning weeks, months, years, we'll need to add support for it here.
    # Go through the trouble of seeing if it is a plural number b/c every time I see something like "1 hours" my eye twitches.
    $duration_string .= join(
        ' ',
        map {
            my $value = $duration->$_;
            $value ? "$value $_" . ( $value > 1 ? 's' : '' ) : ();
        } qw(days hours minutes)
    );

    return {
        'string' => $duration_string,
        'object' => \$duration
    };
}

=head2 simple_date_parser($date, $tzid)

Takes a string like '20230822T005229Z', or '20230822T005229' with the timezone id after it, like 'America/Chicago', and returns a DateTime object

=cut

sub simple_date_parser {
    my ( $self, $date, $tzid ) = @_;
    logfunc();
    dbg("simple_date_parser: Parsing date ~[$date]~ with TZID ~[$tzid]~");

    require DateTime::Format::Strptime;

    my $pattern = '%Y%m%dT%H%M%S';
    if ( substr( $date, -1 ) eq 'Z' ) {
        $pattern = '%Y%m%dT%H%M%S%z';
    }

    # Run the tzid through the Win32 mapping to fix cases where the event is from Outlook
    $tzid = _fix_tzid_if_needed($tzid);

    # If we didn't get a timezone id, default to UTC
    my $strptime = DateTime::Format::Strptime->new(
        pattern   => $pattern,
        time_zone => $tzid // 'UTC'
    );

    my $dt_obj = $strptime->parse_datetime($date);
    return $dt_obj;
}

=head2 get_events_info($original_ics_data_sr)

Take the vevent text and parse it into something fairly easily digestable
returns an array ref of all the events (99% of the time it's just one) along with
the names and values, as well as any additional parameters.

Notes:

=over

=item * Properties in @unique will only have one value, while properties in @multiple will be returned as an array

=item * This should be used as a one-way street to get information, it can't be easily used to write out a vcard with Text::VCardFast

=back

=cut

sub get_events_info {
    my ( $self, $original_ics_data_sr ) = @_;
    logfunc();
    my @unique = ( 'description', 'summary', 'transp', 'last-modified', 'dtend', 'dtstart', 'dtstamp', 'organizer', 'created', 'location', 'uid' );

    my $p_hr;
    eval {
        if ( ref($original_ics_data_sr) ne 'SCALAR' || !defined($$original_ics_data_sr) ) {
            dbg("_[get_events_info]_ : ![provided data was not a scalar ref]!");
            require Carp;
            Carp::croak('provided data was not a scalar ref');
        }
        $p_hr = Text::VCardFast::vcard2hash( ${$original_ics_data_sr} );
    };
    if ($@) {
        dbg( "_[get_events_info]_ : !!!!!!!!! failed to parse content:", $@, $original_ics_data_sr );
        return [];
    }
    my @events;
    foreach my $vcalendar ( @{ $p_hr->{'objects'} } ) {
        foreach my $part ( @{ $vcalendar->{'objects'} } ) {
            if ( $part->{'type'} eq 'vevent' ) {
                my %event_info;
                my $event_properties_hr = $part->{'properties'};
                foreach my $prop_key ( keys %{$event_properties_hr} ) {
                    foreach my $prop ( @{ $event_properties_hr->{$prop_key} } ) {
                        my $prop_name = $prop->{'name'} || $prop_key;
                        my %params_info;
                        if ( defined $prop->{'params'} ) {
                            foreach my $param_key ( keys %{ $prop->{'params'} } ) {
                                foreach my $param_element ( @{ $prop->{'params'}->{$param_key} } ) {
                                    $params_info{$param_key} = $param_element;
                                }
                            }
                        }
                        if ( grep { $_ eq $prop_name } @unique ) {
                            $event_info{$prop_name} = { 'value' => $prop->{'value'}, 'params' => \%params_info };

                            #                         } elsif( grep { $_ eq $prop_name } @multiple ) {
                            #                             push( @{$event_info{$prop_name}}, { 'value' => $prop->{'value'}, 'params' => \%params_info } );
                        }
                        else {
                            push( @{ $event_info{$prop_name} }, { 'value' => $prop->{'value'}, 'params' => \%params_info } );
                        }
                    }
                }
                push( @events, \%event_info );
            }
        }
    }
    return \@events;
}

=head2 parse_itip_data($original_ics_data_sr)

Similar to get_events_info(), but focuses on iTIP message information, primarily for freebusy request handling

=cut

sub parse_itip_data {
    my ( $self, $original_ics_data_sr ) = @_;
    logfunc();
    my @unique = ( 'description', 'summary', 'transp', 'last-modified', 'dtend', 'dtstart', 'dtstamp', 'organizer', 'created', 'location', 'uid' );

    my $p_hr;
    eval { $p_hr = Text::VCardFast::vcard2hash( ${$original_ics_data_sr} ); };
    if ($@) {
        dbg( "_[parse_itip_data]_ : failed to parse ICS data: ", $@, $original_ics_data_sr );
        return [];
    }

    # dbg("_[parse_itip_data]_ : initial parse : ", $p_hr );
    my @events;
    foreach my $vcalendar ( @{ $p_hr->{'objects'} } ) {

        #         dbg("_[parse_itip_data]_ : VCALENDAR : ", $vcalendar );
        if ( $vcalendar->{'type'} eq 'vcalendar' ) {
            my %event_info;

            # Parse the high-level properties of the VCALENDAR itself (unsure if we need this)
            my $vcalendar_properties_hr = delete $vcalendar->{'properties'};
            foreach my $prop_key ( keys %{$vcalendar_properties_hr} ) {
                foreach my $prop ( @{ $vcalendar_properties_hr->{$prop_key} } ) {
                    my $prop_name = $prop->{'name'} || $prop_key;
                    my %params_info;
                    if ( defined $prop->{'params'} ) {
                        foreach my $param_key ( keys %{ $prop->{'params'} } ) {
                            foreach my $param_element ( @{ $prop->{'params'}->{$param_key} } ) {
                                $params_info{$param_key} = $param_element;
                            }
                        }
                    }
                    if ( grep { $_ eq $prop_name } @unique ) {
                        $event_info{'vcalendar'}{$prop_name} = { 'value' => $prop->{'value'}, 'params' => \%params_info };
                    }
                    else {
                        push( @{ $event_info{'vcalendar'}{$prop_name} }, { 'value' => $prop->{'value'}, 'params' => \%params_info } );
                    }
                }
            }

            # Iterate through all the remaining sections and build data structure
            foreach my $section ( @{ $vcalendar->{'objects'} } ) {
                my $section_properties = delete $section->{'properties'};

                # dbg("_[parse_itip_data]_ : section properties: ", $section_properties );
                my $section_type = $section->{'type'};
                if ( length $section_type ) {

                    # dbg("_[parse_itip_data]_ : found a freebusy section: ",  $section);
                    foreach my $prop_key ( keys %{$section_properties} ) {

                        # dbg("_[parse_itip_data]_ : prop_key : $prop_key");
                        foreach my $prop ( @{ $section_properties->{$prop_key} } ) {
                            my $prop_name = $prop->{'name'} || $prop_key;
                            my %params_info;
                            if ( defined $prop->{'params'} ) {
                                foreach my $param_key ( keys %{ $prop->{'params'} } ) {
                                    foreach my $param_element ( @{ $prop->{'params'}->{$param_key} } ) {
                                        $params_info{$param_key} = $param_element;
                                    }
                                }
                            }
                            if ( grep { $_ eq $prop_name } @unique ) {
                                $event_info{$section_type}{$prop_name} = { 'value' => $prop->{'value'}, 'params' => \%params_info };
                            }
                            else {
                                push( @{ $event_info{$section_type}{$prop_name} }, { 'value' => $prop->{'value'}, 'params' => \%params_info } );
                            }
                        }
                    }
                }
                else {
                    dbg( "_[parse_itip_data]_ : section in itip message is missing a type ? ", $section );
                }
            }
            push( @events, \%event_info );
        }
    }
    return \@events;
}

=head2 insert_invite_data_to_vcard($original_ics_data_sr)

Generates and adds an X-CPANEL-ID: entry to the ics, as well as METHOD:REQUEST and SENT-BY: for the system user that processes replies

=cut

sub insert_invite_data_to_vcard {
    my ( $self, $original_ics_data_sr ) = @_;    # add $self to fin vers
    logfunc();
    dbg( "_[insert_invite_data_to_vcard]_ entered : ", $self, $$$original_ics_data_sr );

    # Find the UID of the event. If we don't find one, it's likely a broken ics and we need to just jump out.
    my %user_cal_uid_hash;
    $user_cal_uid_hash{'user'} = $self->{'request_info'}{'principal_user'};
    $user_cal_uid_hash{'cal'}  = $self->{'request_info'}{'collection'};
    $user_cal_uid_hash{'uid'}  = '';
    my @full_vcard = split( /\r\n|\n/, $$$original_ics_data_sr );

    foreach my $line (@full_vcard) {
        chomp($line);
        if ( $line =~ m/^UID\:(.+)/ ) {
            $user_cal_uid_hash{'uid'} = $1;
            last;
        }
    }
    if ( !defined $user_cal_uid_hash{'uid'} ) {
        dbg("_[insert_invite_data_to_vcard]_ : ![Could not find UID in event file. Returning original, unmodified event data.]!");
        return $original_ics_data_sr;
    }
    else {
        dbg( "_[insert_invite_data_to_vcard]_ : user_cal_uid_hash is: ", \%user_cal_uid_hash );
    }

    require Cpanel::JSON;

    # Generate the x-cpanel-id data. we take a hash of user,cal,uid vales, serialize them with json, base64 encode it, then fold it at the right length for a vcard
    my $user_cal_uid_json    = Cpanel::JSON::Dump( \%user_cal_uid_hash );
    my $x_cpanel_id          = MIME::Base64::encode_base64( $user_cal_uid_json, '' );
    my $x_cpanel_id_fullline = 'X-CPANEL-ID:' . $x_cpanel_id;
    my $chunks_ar            = fold_string( $x_cpanel_id_fullline, 74 );                # cut it at 74 to be sure it's wrapped early enough
    $x_cpanel_id_fullline = join( "\r\n", @{$chunks_ar} );
    dbg( "_[insert_invite_data_to_vcard]_ : adding our line to original vcf:", $x_cpanel_id_fullline );

    my $method_request = "METHOD:REQUEST";

    #     require Cpanel::Sys::Hostname;
    #     my $hostname = Cpanel::Sys::Hostname::gethostname();
    #     my $sent_by = 'SENT-BY="mailto:cpanel-eventinvites@' . $hostname . '"';

    my $index = 0;
    $index++ until $full_vcard[$index] =~ m/^BEGIN\:VCALENDAR/;
    splice( @full_vcard, $index + 1, 0, $method_request );
    $index++ until $full_vcard[$index] =~ m/^BEGIN\:VEVENT/;
    splice( @full_vcard, $index + 1, 0, $x_cpanel_id_fullline );

    #     $index++ until $full_vcard[$index] =~ m/^ORGANIZER(.+)/;
    #     splice( @full_vcard, $index + 0, 1, "ORGANIZER;" . $sent_by . $1 );
    my $modified_ics_data = join( "\r\n", @full_vcard );
    return \$modified_ics_data;
}

=head2 find_key_and_collect_matches($structure, $search_key)

Function to search for a specific key in a nested structure. Returns an array ref of matches.

(should probably be private)

=cut

sub find_key_and_collect_matches {
    my ( $self, $structure, $search_key ) = @_;

    #     dbg("find_key_and_collect_matches : entering: ", $self, $structure, $search_key );
    my @matches;

    if ( ref($structure) eq 'HASH' ) {
        if ( exists $structure->{$search_key} ) {
            push @matches, $structure->{$search_key};
        }
        foreach my $value ( values %$structure ) {
            push @matches, @{ $self->find_key_and_collect_matches( $value, $search_key ) };
        }
    }
    elsif ( ref($structure) eq 'ARRAY' ) {
        foreach my $value (@$structure) {
            push @matches, @{ $self->find_key_and_collect_matches( $value, $search_key ) };
        }
    }

    #     dbg("find_key_and_collect_matches : returning : ", \@matches );
    return \@matches;
}

sub _delete_xml {
    my ( $dom, $path ) = @_;
    logfunc();
    my $response = $dom->createElement("d:response");
    $response->appendTextChild( "d:href"   => $path );
    $response->appendTextChild( "d:status" => "HTTP/1.1 401 Permission Denied" );    # *** FIXME ***
    return;
}

# return the parent directory of this path

sub _parentdir {
    my ( $self, $path ) = @_;
    logfunc();
    dbg("_[_parentdir]_ : in : ([$path])");
    $path = $self->_safepath($path);

    # The path can be an absolute filesystem path or a relative URI path
    if ( $path eq "/" ) {
        return "/";
    }
    else {
        $path =~ s/\/[^\/]+\/?$//;
    }
    dbg("_[_parentdir]_ : out : ([$path])");
    return $path;
}

sub _delete {
    my ( $self, $request, $response ) = @_;
    logfunc();
    my $path = $self->{'request_info'}{'fs_root'};
    if ( !$self->check_write_access( scalar($path) ) ) {
        dbg("_[_delete]_ : User does not have write access to the path ([$path])");
        $response->code(403);
        $response->message('Forbidden');
        return;
    }

    if ( $request->uri->fragment ) {
        dbg("_[_delete]_ : Request URI was fragmented");
        $response->code(404);
        $response->message('Fragment');
        return;
    }

    unless ( -e $path ) {
        dbg("_[_delete]_ : ([$path]) does not exist");
        $response->code(404);
        return;
    }

    # https://datatracker.ietf.org/doc/html/rfc8607#section-3.9 says that users can not directly call DELETE on attachments. You have to delete it by omission it
    # in a subsequent PUT request for an event that had the attachment before. Why the powers that be couldn't allow it as long as the original .ics is updated.. who knows.
    if ( $path =~ m/\/.+\-attachment\-.+/ ) {
        dbg("_[_delete]_ : Attempt was made to directly delete an attachment, which is forbidden");
        $response->code(403);
        $response->message('Forbidden');
        return;
    }

    my $dom = XML::LibXML::Document->new( "1.0", "utf-8" );
    my @error;

    my @parts;

    #     if( -d $path ) {
    #         @parts = File::Find::Rule->file()
    #                                   ->name()
    #                                   ->in( $path );
    #     }
    if ( -f $path ) {
        my @path_bits = split( /\//, $path );
        my $filename  = pop @path_bits;
        my $dirpath   = join( '/', @path_bits );
        @parts = File::Find::Rule->file()->any( File::Find::Rule->name($filename), File::Find::Rule->name( $filename . '-attachment-*' ) )->in($dirpath);
    }
    else {
        @parts = reverse sort
          grep { $_ !~ m{/\.\.?$} }
          map { s{/+}{/}gr } File::Find::Rule->in($path);
        push @parts, $path;
    }

    dbg( "_[_delete]_ : stuff to delete:", \@parts );

    # Search for default calendar before actually deleting files
    my @allowed_to_delete;
    foreach my $path_to_rm (@parts) {
        if ( -d $path_to_rm ) {
            if ( grep { /\/calendar(\/)?$/ } ( $request->uri->path, $path_to_rm ) ) {
                dbg("_[_delete]_ : Matched default calendar in request URI and also path");

                # use _delete_xml to show it could not remove this ?
                # remove all paths matching this from @parts, or just push stuff that doesn't match it to a new array and use that below.
                $response->code(403);
                $response->message('Forbidden');
                return;
            }
            push( @allowed_to_delete, $path_to_rm );
        }
        elsif ( -f _ ) {
            push( @allowed_to_delete, $path_to_rm );
        }
    }
    undef @parts;

    foreach my $path_to_rm (@allowed_to_delete) {
        next unless ( -e $path_to_rm );

        # in order to be able to delete something, we need write access to the parent directory
        if ( $self->check_write_access( $self->_parentdir($path_to_rm) ) ) {
            my $fb_file_path = $self->{'request_info'}{'fb_file_path'};
            if ( -f $path_to_rm ) {
                dbg( "_[_delete]_ : request to delete apparent file: $path_to_rm", $self );

                # The UID and filename are not always the same, so we need to open the file before deleting it to get the UID from it.
                # All events will be part of a collection, so without that, we don't want to get in here
                if ( length $self->{'request_info'}{'collection'} ) {
                    my $collection = $self->{'request_info'}{'collection'};
                    if ( open( my $about_to_be_deleted_ics_fh, '<', $path_to_rm ) ) {
                        my $raw_ics;
                        while (<$about_to_be_deleted_ics_fh>) {
                            $raw_ics .= $_;
                        }
                        close($about_to_be_deleted_ics_fh);
                        dbg("_[_delete]_ : decline before delete");
                        local $@;
                        eval { my $err_code = $self->_update_partstat_for_attendee( $self->{'request_info'}{'principal_user'}, $path_to_rm, \$raw_ics ); };
                        dbg("_[_delete]_ : ![failed to decline invitation]! $@") if ($@);
                        my $events_ar = $self->get_events_info( \$raw_ics );
                        my $fbdata_hr = get_freebusy_data_from_parsed_ics($events_ar);
                        dbg( "_[_delete]_ : this is the event we need to delete:", $fbdata_hr );

                        # Need to add $fbdata_hr to the collection it is under.
                        my $fbdata_col_hr;
                        $fbdata_col_hr->{$collection} = $fbdata_hr;
                        dbg( "_[_delete]_ : here it is including the collection :", $fbdata_col_hr );

                        if ( unlink($path_to_rm) ) {

                            # Remove the event from the FB data.
                            remove_freebusy_data( $fb_file_path, $self->{'sys_user'}, $fbdata_col_hr );
                        }
                        else {
                            dbg("_[_delete]_ : Failed to remove $path_to_rm : $!");
                            push( @error, _delete_xml( $dom, $path_to_rm ) );
                        }

                    }
                }
                else {
                    dbg( "_[_delete]_ : No collection in request ?", $self );
                }
            }
            elsif ( -d $path_to_rm ) {

                # HB-7213 - large
                #      - need to consider if we event want to allow this ?
                #        the only directory a user would even have access to is the collection directory, and we probably
                #        want to limit removing that to the UI itself for the time being. Once we support MKCOL and friends this is a more legit pathway.
                #      - be sure to include removing the collection from the FB data when doing this
                #      - note that schedule-default-calendar-URL (currently not supported) declares the default calendar for scheduling, and RFC 6638 4.3 says servers MUST
                #        reject any attempt to delete the default calendar collection.
                #      - DELETE on the collection being shared is how clients are supposed to remove sharees, as described in https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-sharing.txt
                #        This does not remove the collection, but instead removes the sharee's access to the collection.
                dbg("_[_delete]_ : request to delete apparent dir: $path_to_rm");

                # Consider using this rather than the file::find stuff above, for dirs ?
                # Or maybe File::Find's rmtree to avoid yet another module ?
                if ( Cpanel::SafeDir::RM::safermdir($path_to_rm) ) {
                    my $collection = $self->{'request_info'}{'collection'};

                    # HB-7213 - small - if $collection, and collection matches last part of $path_to_rm , create an empty collection and send to remove_freebusy_data
                    my $fbdata_col_hr;
                    $fbdata_col_hr->{$collection} = $collection;
                    remove_freebusy_data( $fb_file_path, $self->{'sys_user'}, $fbdata_col_hr );
                }
                else {
                    dbg("_[_delete]_ : Failed to remove $path_to_rm : $!");
                    push( @error, _delete_xml( $dom, $path_to_rm ) );
                }
            }
        }
        else {
            dbg("_[_delete]_ : request to delete something not allowed by ACL / check_write_access : $path_to_rm");
            push @error, _delete_xml( $dom, $path_to_rm );
        }
    }

    if (@error) {
        my $multistatus = $dom->createElement("D:multistatus");
        $multistatus->setAttribute( "xmlns:D", "DAV:" );

        $multistatus->addChild($_) foreach @error;

        $response->code(207);
        $response->message("Multi-Status");
        $response->header( "Content-Type" => 'text/xml; charset="utf-8"' );
    }
    else {
        $response->code(204);
    }
    return;
}

sub _destination {
    my ( $self, $request ) = @_;
    logfunc();
    my $destination = URI->new( $request->header('Destination') )->path;
    $destination = realpath( "/" . $self->{auth_user_caldav_root} . "/" . $destination );
    $destination =~ s/\/\/+/\//g;

    return $destination;
}

sub _min {
    my ( $a, $b ) = @_;
    logfunc();
    if ( $a < $b ) {
        return $a;
    }
    else {
        return $b;
    }
}

sub _parse_calendar_timezone {
    my ( $self, $tzdata ) = @_;
    logfunc();

    #my %parsed_data;
    my $current_key = '';

    my @vcard;
    foreach my $line ( split( /\n/, $tzdata ) ) {
        chomp($line);
        push( @vcard, $line );
    }
    return;

    #   We already ship Text::VCardFast, so we can use Text::VCardFast::vcard2hash($card) to get the hash, BUT it won't parse an individual line,
    #   so we either need to fake it or ship Text::vFile::asData

    #    This module needs to be added to the cpanel-cpan mods before builds will work off this
    #    my $data = Text::vFile::asData->new->parse_lines(@vcard);
    #    dbg( "ical parsed is ", $data );

    # 	for my $line (split /\n/, $tzdata) {
    # dbg(" _parse_calendar_timezone line is $line , current_key is $current_key");
    # 		if ($line =~ /^BEGIN:(.+)$/) {
    # 			$current_key = $1;
    # 		} elsif ($line =~ /^END:(.+)$/) {
    # 			$current_key = '';
    # 		} elsif ($line =~ /^(.+):(.+)$/) {
    # 			$parsed_data{$current_key}{$1} = $2 if $current_key;
    # 		}
    # 	}
    # 	dbg("_parse_calendar_timezone parsed the tzdata to", \%parsed_data );
    #    return $data;
}

sub _parse_request_payload {    ##no critic(Subroutines::ProhibitExcessComplexity)
    my ( $self, $request, $response ) = @_;
    logfunc();

    #     dbg( "{[_parse_request_payload]}:", $request, $response );
    my $content;
    my @hrefs;
    my $reqtype;
    my $reqtype_ns;
    my @reqprops;
    my $user_agent;
    my $reqinfo = '';
    my %search_query;

    if ( !$request->header('Content-Length') ) {
        dbg( "{[_parse_request_payload]} No Content-Length in request ?? ", $request );
        return undef;
    }
    $content    = $request->content();
    $user_agent = $request->header('User-Agent') || 'N/A';
    dbg("*[_parse_request_payload]* User-Agent: $user_agent");
    dbg("\n== [ REQUEST PAYLOAD ] ==============================\n*[$content]*\n=================================================");
    my $parser = XML::LibXML->new;
    my $doc;
    eval { $doc = $parser->parse_string($content); };

    if ($@) {
        $response->code(400);
        $response->message('Bad Request');
        $response->content("Error: $@");
        dbg("*[_parse_request_payload]* : ![failed to parse request content]! $@");
        goto QUICKEXIT;
    }

    my $toplevel = $doc->find('/*')->shift;

    # dbg( "*[_parse_request_payload]* : toplevel : ", $toplevel );
    $reqtype    = $toplevel->localname;
    $reqtype_ns = $toplevel->namespaceURI;

    dbg("*[_parse_request_payload]* : reqtype = *[$reqtype]* , =[$reqtype_ns]=");
    iolog(">>TYPE( $reqtype_ns $reqtype )");

    my $reqinfo_element = $doc->findnodes('/*/*')->shift;
    if ($reqinfo_element) {
        $reqinfo = $reqinfo_element->localname;
        dbg("*[_parse_request_payload]* : reqinfo = *[$reqinfo]*");
    }
    else {
        dbg("*[_parse_request_payload]* : NO reqinfo in XML payload");
    }

    # Handle various request types

    # principal-property-search can have mulitple property-search elements, each defining one prop element
    # additionally it can include a prop element that contains any number of properties to return for each matching principal
    if ( $reqtype eq 'principal-property-search' ) {
        my $reqtype_attr_test = $toplevel->getAttribute('test');    # anyof or allof, so *$matchme* or ^$matchme$
        $self->{'search_query_type'} = $reqtype_attr_test;

        dbg("*[_parse_request_payload]* test attr = $reqtype_attr_test");
        if ( $reqinfo eq 'property-search' ) {
            dbg("*[_parse_request_payload]* doing property-search things..");

            # Get info on what the client is searching for
            # Use of local-name() w/ XPath search syntax avoids needing to know the namespace mapping of what we are looking for; that's very strict for what we are doing here

            # There can be other types here besides prop and match, such as time-range <A:time-range start="20230913T000000Z" end="20230914T000000Z"/> , but I'll need
            # to see it in practice before having confidence in parsing it correctly.

            for my $property_search_node ( $doc->findnodes('.//*[local-name()="property-search"]') ) {
                dbg("*[_parse_request_payload]* prop search node {[$property_search_node]}");
                my $search_prop_element = $property_search_node->find('.//*[local-name()="prop"]/*')->[0];

                dbg( "*[_parse_request_payload]* prop search node prop ele1 = $search_prop_element , " . $search_prop_element->localname );
                my $search_prop_element_name = $search_prop_element->localname;
                dbg("*[_parse_request_payload]* prop localname is $search_prop_element_name");
                $search_query{$search_prop_element_name}{'ns'} = $search_prop_element->namespaceURI;

                my $match_element = $property_search_node->find('.//*[local-name()="match"]')->[0];
                dbg( "*[_parse_request_payload]* match element is ", $match_element );
                if ($match_element) {
                    my $match_type = $match_element->getAttribute('match-type');
                    my $match_text = $match_element->textContent();
                    $search_query{$search_prop_element_name}{'match-type'} = $match_type;
                    $search_query{$search_prop_element_name}{'match-text'} = $match_text;
                }

                # Possibly add other stuff here, like time-range. add as encountered in the wild.
            }

            # Get any additional properties outside the scope of property-search. These are the properties to return for what property-search matches
            my @prop_elements_blocks = $doc->findnodes('.//*[local-name()="principal-property-search"]/*[local-name()="prop" and not(ancestor::*[local-name()="property-search"])]');
            dbg( "*[_parse_request_payload]* top level props element: ", \@prop_elements_blocks );
            foreach my $prop_element (@prop_elements_blocks) {
                dbg( "*[_parse_request_payload]* top level prop : ", $prop_element->toString );
                foreach my $node ( $prop_element->findnodes('.//*') ) {
                    dbg( "*[_parse_request_payload]* ze prop eez : ", $node );
                    push @reqprops, [ $node->namespaceURI, $node->localname, $node->textContent() ];
                }
            }

        }
        dbg( "search query: ", \%search_query );
    }
    elsif ( $reqtype eq 'calendar-multiget' || $reqtype eq 'addressbook-multiget' ) {
        for my $node ( $doc->find('/*/*')->get_nodelist ) {
            my $propname = $node->localname;
            dbg("*[_parse_request_payload]* thing is $node AKA $propname");
            if ( $propname eq 'href' ) {
                push @hrefs, $node->textContent();
            }
        }
    }

    #         elsif ( $reqtype eq 'sync-collection' ) {
    #             dbg("INSIDE SYNC-COLLECTION LOGIC IN PARSER");
    #             for my $node ( $doc->find('/*/*')->get_nodelist ) {
    #                 my $propname = $node->localname;
    #                 dbg("_parse_request_payload SYNC-COLLECTION thing is $node AKA $propname");
    #                 if ( $propname eq 'sync-token' || $propname eq 'sync-level' ) {
    #                     push @reqprops, [ $node->namespaceURI, $node->localname, $node->textContent() ];
    #                 }
    #             }
    #             for my $node ( $doc->find('/*/*/*')->get_nodelist ) {
    #                 my $propname = $node->localname;
    #                 dbg("_parse_request_payload (prop?) thing is $node AKA $propname");
    #                 push @reqprops, [ $node->namespaceURI, $node->localname, $node->textContent() ];
    #             }
    #         }
    elsif ( $reqtype eq 'propertyupdate' ) {
        for my $node ( $doc->find('/*/*/*/*')->get_nodelist ) {
            my $propname = $node->localname;
            dbg("*[_parse_request_payload]* (property-update) thing is $node AKA $propname");
            push @reqprops, [ $node->namespaceURI, $node->localname, $node->textContent() ];
        }
    }
    elsif ( $reqtype eq 'expand-property' ) {

        # 			my $xpath = '/*/*[@name="calendar-proxy-write-for"]';
        # 			my @nodes = $doc->findnodes($xpath);
        # 			dbg( "XPATH NODES IS " , \@nodes );
        # 			foreach my $n( @nodes ) {
        # 				dbg("XPATH node is $n");
        # 				dbg( "XPATH parentnode is  $n->parentNode " );
        # 			}

        for my $node ( $doc->find('/*/*')->get_nodelist ) {

            # Do this once for the parent node, then same thing again for each child node. If we find a use case where this
            # gets nested more deeply we'll probably need to make this more complicated with recursive functionality.
            my $propname = $node->localname;
            next if !$propname;
            dbg("*[_parse_request_payload]* /*/* PARENT _parse_request_payload on /*/* thing is $node AKA $propname");
            my ( $parent_name, $parent_namespace );
            my @attrs = $node->attributes();
            foreach my $attrib (@attrs) {
                my ( $key, $value ) = split( /\=/, $attrib, 2 );
                $key   =~ s/^\s+|\s+$//g;
                $value =~ s/^\"+|\"+$//g;
                dbg("*[_parse_request_payload]* /*/* PARENT property request has the following attribute: ($key) = ($value)");
                if ( $key eq 'name' ) {
                    dbg("*[_parse_request_payload]* /*/* PARENT assigning name = $value");
                    $parent_name = $value;
                }
                elsif ( $key eq 'namespace' ) {
                    dbg("*[_parse_request_payload]* /*/* PARENT assigning namespace = $value");
                    $parent_namespace = $value;
                }
            }
            dbg("*[_parse_request_payload]* /*/* PARENT adding $parent_namespace > $parent_name to reqprops");

            if ( $node->hasChildNodes() ) {
                my @child_nodes = $node->childNodes();
                my @child_reqprops;
                dbg("*[_parse_request_payload]* /*/* PARENT node has child nodes: @child_nodes");
                foreach my $child_node (@child_nodes) {
                    my $propname = $child_node->localname;
                    next if !$propname;
                    dbg("*[_parse_request_payload]* /*/* CHILD _parse_request_payload on /*/* thing is $child_node AKA $propname");
                    my ( $name, $namespace );
                    my @attrs = $child_node->attributes();
                    foreach my $attrib (@attrs) {
                        my ( $key, $value ) = split( /\=/, $attrib, 2 );
                        $key   =~ s/^\s+|\s+$//g;
                        $value =~ s/^\"+|\"+$//g;
                        dbg("*[_parse_request_payload]* /*/* CHILD property request has the following attribute: ($key) = ($value)");
                        if ( $key eq 'name' ) {
                            dbg("*[_parse_request_payload]* /*/* CHILD assigning name = $value");
                            $name = $value;
                        }
                        elsif ( $key eq 'namespace' ) {
                            dbg("*[_parse_request_payload]* /*/* CHILD assigning namespace = $value");
                            $namespace = $value;
                        }
                    }
                    if ( $name and $namespace ) {
                        dbg("*[_parse_request_payload]* /*/* CHILD adding $namespace > $name to child_reqprops");
                        push @child_reqprops, [ $namespace, $name ];
                    }
                    else {
                        dbg("*[_parse_request_payload]* /*/* CHILD could not parse out a name and namespace");
                    }
                }
                push @reqprops, [ { 'parent_name' => $parent_name, 'parent_namespace' => $parent_namespace, 'subprops' => [@child_reqprops], 'child_nodes_xml' => "@child_nodes" } ];
            }
            else {
                push @reqprops, [ $parent_namespace, $parent_name ];
            }

        }

        # 			for my $node ($doc->find('/*/*/*')->get_nodelist) {
        # 				my $propname = $node->localname;
        # 				dbg( "_parse_request_payload thing is $node AKA $propname" );
        # 				if( $propname eq 'property' ) {
        # 					my ( $name, $namespace );
        # 					my @attrs = $node->attributes();
        # 					foreach my $attrib ( @attrs ) {
        # 						my( $key, $value ) = split(/\=/, $attrib, 2);
        # 						$key =~ s/^\s+|\s+$//g;
        # 						$value =~ s/^\"+|\"+$//g;
        # 						dbg( "property request has the following attribute: ($key) = ($value)" );
        # 						if( $key eq 'name' ) {
        # 							dbg( "assigning name = $value" );
        # 							$name = $value;
        # 						} elsif( $key eq 'namespace' ) {
        # 						dbg( "assigning namespace = $value" );
        # 							$namespace = $value;
        # 						}
        # 					}
        # 					dbg( "name is $name and ns is $namespace" );
        # 					if( length($name) > 0 && length($namespace) > 0 ) {
        # 						dbg( "adding $namespace > $name to reqprops" );
        # 						push @reqprops, [ $namespace, $name ];
        # 					}
        # 				} else {
        # 					dbg( "propname is $propname, but we only know about 'property' right now" );
        # 				}
        # 			}
    }

    if ( $reqinfo eq 'prop' ) {
        for my $node ( $doc->find('/*/*/*')->get_nodelist ) {
            dbg( "*[_parse_request_payload]* node is " . $node->toString() );
            push @reqprops, [ $node->namespaceURI, $node->localname ];
        }
    }

    return {
        'method'      => $request->method(),
        'req_payload' => $content,
        'hrefs'       => \@hrefs,
        'reqtype'     => $reqtype,
        'reqtype_ns'  => $reqtype_ns,
        'reqprops'    => \@reqprops,
        'user_agent'  => $user_agent,
        'reqinfo'     => $reqinfo,
        'search_data' => \%search_query
    };
}

sub _is_path_owned_by_user {
    my ( $self, $path ) = @_;
    logfunc();
    dbg("_is_path_owned_by_user , ([$path]) ?");
    if ( defined $self->{'request_info'}{'principal_user'} && $self->{'request_info'}{'principal_user'} eq $self->{'auth_user'} ) {
        dbg("_[_is_path_owned_by_user]_ : returning 1");
        return 1;
    }

    dbg("_is_path_owned_by_user : returning 0");
    return 0;
}

# Give this function a file system path and it will return the base path to their caldav data, such as /home/sysuser/.caldav/caldavuser/
sub _get_principal_base_path {
    my ( $self, $path ) = @_;
    logfunc();
    my @path_parts = split( '/', $path );

    my $seen_caldav = 0;
    my @base_path_parts;

    # See if the requested path and the authed user path are based in the same .caldav/ directory
    for my $i ( 0 .. scalar(@path_parts) ) {
        push( @base_path_parts, $path_parts[$i] );
        last if $seen_caldav;
        if ( $path_parts[$i] eq '.caldav' ) {
            $seen_caldav = 1;
        }
    }
    if ( !$seen_caldav ) {
        dbg("_[_get_principal_base_path]_ : Could not find .caldav in the given path, ([$path]), so returning undef");
        return undef;
    }
    else {
        dbg("_[_get_principal_base_path]_ : Found .caldav in the given path, ([$path]), so joining the following with / and returning ([@base_path_parts])");
        return join( '/', @base_path_parts );
    }
}

sub _get_metadata_property {
    my ( $self, $path, $property ) = @_;
    logfunc();
    my $path_hr = $self->_parse_request_path($path);

    #     dbg( "=[_get_metadata_property]= : PATH: ([$path]), property = -[$property]-, path_hr and self:", $path_hr, $self );
    dbg("=[_get_metadata_property]= : PATH: ([$path]), property = -[$property]-");
    if ( $property eq 'calendar-description' or $property eq 'addressbook-description' ) {
        $property = 'description';
    }
    my $existing_metadata_hr;
    my $user_base_path = $self->_get_principal_base_path($path);
    dbg("=[_get_metadata_property]= : loading metadata from ([$user_base_path])");
    $existing_metadata_hr = $self->{'metadata'}->load( $user_base_path . '/.metadata' );

    my $collection_path = $path_hr->{'collection'} if length $path_hr->{'collection'};
    $collection_path //= '';

    my $owner_principal = $path_hr->{'principal_user'};
    if ( $owner_principal ne $self->{'username'} ) {

        my $existing_authuser_metadata_hr = $self->{'metadata'}->load();
        dbg( "=[_get_metadata_property]= : existing_metadata_hr and existing_authuser_metadata_hr, collection_path=([$collection_path]),  property=-[$property]- :", $existing_metadata_hr, $existing_authuser_metadata_hr );
        if ( exists $existing_authuser_metadata_hr->{ '///' . $owner_principal . '///' . $collection_path }{$property} ) {
            if ( $property eq 'displayname' ) {

                # Dynamically show the owner in collections just for the displayname property, with the caveat that we don't add it if it's already in there (happens when a user changes the name of a shared calendar but doesn't delete the appended owner principal)
                if ( $existing_authuser_metadata_hr->{ '///' . $owner_principal . '///' . $collection_path }{$property} =~ m/$owner_principal/ ) {
                    return $existing_authuser_metadata_hr->{ '///' . $owner_principal . '///' . $collection_path }{$property};
                }
                else {
                    return $existing_authuser_metadata_hr->{ '///' . $owner_principal . '///' . $collection_path }{$property} . ' (' . $owner_principal . ')';
                }
            }
            dbg("=[_get_metadata_property]= : found shared (from $owner_principal) override property for $collection_path : $existing_authuser_metadata_hr->{'///'.$owner_principal.'///'.$collection_path}{$property}");
            return $existing_authuser_metadata_hr->{ '///' . $owner_principal . '///' . $collection_path }{$property};
        }
        elsif ( exists $existing_metadata_hr->{$collection_path}{$property} ) {
            if ( $property eq 'displayname' ) {
                return $existing_metadata_hr->{$collection_path}{$property} . ' (' . $owner_principal . ')';    # Dynamically show the owner in collections just for the displayname property
            }
            return $existing_metadata_hr->{$collection_path}{$property};
        }
        else {
            dbg("=[_get_metadata_property]= : could not find -[$property]- in ([$collection_path]) for either auth user or owner principal's metadata..");
        }
    }
    else {
        if ( $collection_path && exists $existing_metadata_hr->{$collection_path} && exists $existing_metadata_hr->{$collection_path}{$property} ) {
            dbg( "=[_get_metadata_property]= : existing_metadata_hr, collection_path=([$collection_path]),  property=-[$property]- :", $existing_metadata_hr );
            return $existing_metadata_hr->{$collection_path}{$property};
        }
        elsif ( $path =~ m/\/(\.caldav)\/(.+)\/$/ ) {

            # Check to see if this is a request to a principal
            dbg("=[_get_metadata_property]= : looks like a request to a principal, returning their user as displayname rather than $collection_path");
            return $collection_path;    # This is needed for some addressbook requests

            #             return $2; # Need to see if/when this makes more sense and account for it
        }
    }
    dbg(" =[_get_metadata_property]= returning empty string since there is no collection with a property of $property in the existing metadata");
    return '';    # Return empty string so we don't get errors comparing undef value to strings
}

sub modify_metadata {
    my ( $self, $data_hr, $path ) = @_;
    logfunc();

    $path ||= $self->{'auth_user_caldav_root'} . '/.metadata';
    dbg( "=[modify_metadata]= data_hr and path:", $data_hr, $path );

    my $path_info_hr = $self->_parse_request_path( $data_hr->{'path'} );
    dbg( "=[modify_metadata]= path info hr on $data_hr->{'path'}  : ", $path_info_hr );

    dbg( "=[modify_metadata]= metadata path ([$path]) and data_hr to save : ", $data_hr );

    # Get the metadata that is relevant for the request # TODO - access check here, or is during save enough ?
    my $existing_metadata_hr = $self->{'metadata'}->load( $path_info_hr->{'metadata_path'} );
    dbg( "=[modify_metadata]= load_metadata returned request path existing_metadata_hr : ", $existing_metadata_hr );

    my $collection = $data_hr->{'path'};
    my $key        = $data_hr->{'propname'};
    my $val        = $data_hr->{'propval'};

    my $collection_path = $self->_virtualpath($collection);
    dbg("=[modify_metadata]= collection path is $collection_path ");

    # If the auth user is not the principal for the resource in question, load metadata for both. Let the auth user's values
    # override the ones for the original principal. When we save it, some specific values are saved to the auth user's metadata, while
    # the rest is saved to the original principal. The auth user's metadata is marked to indicate it is overriding values from a shared collection. We only need
    # to save the values we override, but a full duplicate is not awful and makes more sense visually.
    my $existing_authuser_metadata_hr;
    my $owner_principal = $path_info_hr->{'principal_user'};
    my $saved_ok        = 0;
    if ( $owner_principal ne $self->{'username'} ) {
        dbg("=[modify_metadata]= loading metadata for auth user ($owner_principal), as we need to overlay that on top of existing_metadata_hr");
        $existing_authuser_metadata_hr = $self->{'metadata'}->load();
        dbg( "=[modify_metadata]= load_metadata returned existing_authuser_metadata_hr : ", $existing_authuser_metadata_hr );

        dbg("=[modify_metadata]= want to take $collection : $key = $val from existing_metadata_hr and save it to existing_authuser_metadata_hr, without overwriting $collection from them..");

        if ( defined( $existing_metadata_hr->{$collection_path} ) ) {
            foreach my $prop ( keys %{ $existing_metadata_hr->{$collection_path} } ) {
                if ( !length $existing_authuser_metadata_hr->{"///$owner_principal///$collection_path"}{$prop} ) {
                    $existing_authuser_metadata_hr->{"///$owner_principal///$collection_path"}{$prop} = $existing_metadata_hr->{$collection_path}{$prop};
                }
            }
        }

        $existing_authuser_metadata_hr->{"///$owner_principal///$collection_path"}{$key} = $val;

        dbg( "=[modify_metadata]= existing_authuser_metadata_hr is now ", $existing_authuser_metadata_hr );
        dbg( "=[modify_metadata]= existing_metadata_hr is now ",          $existing_metadata_hr );
        $saved_ok = $self->{'metadata'}->save($existing_authuser_metadata_hr);
    }
    else {
        # Just save to the auth user as they own the collection in question
        $existing_metadata_hr->{$collection_path}{$key} = $val;

        # dbg("=[modify_metadata]= metadata_hr is now ", $existing_metadata_hr );
        $saved_ok = $self->{'metadata'}->save($existing_metadata_hr);
    }

    return $saved_ok;
}

sub _proppatch {
    my ( $self, $request, $response, $c ) = @_;
    logfunc();

    my $path = $self->{'request_info'}{'fs_root'};

    my $access_granted = 0;
    if ( $self->check_write_access( $request->uri->path ) ) {
        $access_granted = 1;
    }
    if ( !$access_granted ) {
        $response->code(403);
        $response->message('User does not have write access to resource');
        return;
    }

    my $parsed_request_hr = $self->_parse_request_payload( $request, $response );

    dbg( "_[_proppatch]_ parsed request is ", $parsed_request_hr );

    my $doc  = XML::LibXML::Document->new( "1.0", "utf-8" );
    my $resp = $doc->createElement("D:multistatus");
    $resp->setAttribute( "xmlns:D", "DAV:" );

    if ( $parsed_request_hr->{'reqinfo'} eq 'set' ) {

        my $resp_xml_element = $doc->createElement('D:response');
        my $href_xml_element = $doc->createElement('D:href');

        #         my $display_path = $self->_get_display_path($path);
        #         $href_xml_element->appendText($display_path); # Saving these two lines in case the one below fails spectatularly in some situation
        $href_xml_element->appendText( $self->{'request_info'}{'uri_decoded_safe'} );
        $resp_xml_element->addChild($href_xml_element);

        my @succeeded;
        my @failed;
        foreach my $prop ( @{ $parsed_request_hr->{'reqprops'} } ) {
            my ( $ns, $propname, $propval ) = @{$prop};
            dbg("_[_proppatch]_ setting =[$ns $propname]= to -[$propval]- on ([$path]) as $self->{'username'}");

            # Only save metadata properties to metadata file
            if ( grep( /\Q$propname\E/, @Cpanel::DAV::Metadata::metadata_props ) ) {
                dbg("_[_proppatch]_ found -[$propname]- in \@Cpanel::DAV::Metadata::metadata_props");
                if ( $propname eq 'calendar-description' or $propname eq 'addressbook-description' ) {
                    $propname = 'description';
                }
                my $modified_ok = $self->modify_metadata( { 'path' => $path, 'propname' => $propname, 'propval' => $propval } );
                if ($modified_ok) {
                    push( @succeeded, { 'ns' => $ns, 'prop' => $propname, 'reqval' => $propval, 'code' => '200', 'msg' => 'OK' } );
                }
                else {
                    push( @failed, { 'ns' => $ns, 'prop' => $propname, 'reqval' => $propval, 'code' => '403', 'msg' => 'Failed' } );
                }
            }
            elsif ( $propname eq 'calendar-availability' ) {    # HB-7214 - medium - refactor this to do the heavy lifting upon submission rather than parsing it when asked
                dbg("_[_proppatch]_ saving -[calendar-availability]-");
                my $avail_path     = $self->{'auth_user_caldav_root'} . '.availability';
                my $tmp_avail_path = $avail_path . '.tmp';
                if ( open( my $avail_fh, '>', $tmp_avail_path ) ) {
                    print $avail_fh $propval;
                    if ( close($avail_fh) ) {
                        if ( _rename( $tmp_avail_path, $avail_path ) ) {
                            dbg("_[_proppatch]_ wrote -[calendar-availability]- data to ([$avail_path])");
                        }
                        else {
                            dbg("_[_proppatch]_ could not rename ([$tmp_avail_path]) to ([$avail_path]) : $!");
                            push( @failed, { 'ns' => $ns, 'prop' => $propname, 'reqval' => $propval, 'code' => '500', 'msg' => 'Could not rename availability temp file to availability file' } );
                        }
                    }
                    else {
                        dbg("_[_proppatch]_ ![Error closing filehandle after writing data to]! ([$tmp_avail_path]) : $!");
                        unlink $tmp_avail_path;
                    }
                }
                else {
                    dbg("_[_proppatch]_ could not write -[calendar-availability]- data to ([$avail_path]) : ![$!]!");
                    push( @failed, { 'ns' => $ns, 'prop' => $propname, 'reqval' => $propval, 'code' => '500', 'msg' => 'Could not write to availability temp file' } );
                }
            }
            elsif ( $propname eq 'group-member-set' ) {
                dbg("_[_proppatch]_ saving -[group-member-set]-");

                # This (proxying) is different than sharing, as it is not collection-aware, just user.
                # The Apple Calendar app, in account settings, allows configuring proxy users directly, and will
                # call PROPPATCH on /principals/user@dom.tld/calendar-proxy-read/ (or calendar-proxy-write) with the following payload:
                #
                # <?xml version="1.0" encoding="UTF-8"?>
                # <A:propertyupdate xmlns:A="DAV:"><A:set><A:prop><A:group-member-set><A:href>/principals/otheruser%40dom.tld/</A:href></A:group-member-set></A:prop></A:set></A:propertyupdate>
                #
                dbg( "_[_proppatch]_ -[group-member-set]- : self at this point is: ", $self );
                my $delegator  = $self->{'request_info'}{'principal_user'};
                my $group_name = $self->{'request_info'}{'tags'}{'calendar-proxy'};    # will either be calendar-proxy-read or calendar-proxy-write
                                                                                       # Our policy server-side is that only the target user can delegate to another user
                if ( $delegator ne $self->{'auth_user'} ) {
                    dbg("_[_proppatch]_ -[group-member-set]- : ![$self->{'auth_user'} is not allowed to modify group-member-set for $delegator]!");
                    push( @failed, { 'ns' => $ns, 'prop' => $propname, 'reqval' => $propval, 'code' => '401', 'msg' => 'Permission denied' } );
                    next;
                }

                # Get the user being added as a delegatee from the payload
                my $delegatee;
                $propval = decode_utf8( URI::Escape::uri_unescape($propval) );         # ensure %40 is converted to @ for storage
                if ( $propval =~ m/principals\/([^\/]+)\/{0,1}$/ ) {                   # so far I've only seen this as '/principals/user%40dom.tld/'
                    $delegatee = $1;
                }
                my %proxy_hash;
                $proxy_hash{$delegator}{$delegatee} = $group_name;
                $self->modify_proxy_config_data( \%proxy_hash );
                dbg( "_[_proppatch]_ -[group-member-set]- proxy config updated, $delegator -> $delegatee", \%proxy_hash );
                push( @succeeded, { 'ns' => $ns, 'prop' => $propname, 'reqval' => $propval, 'code' => '200', 'msg' => 'OK' } );

            }
            else {
                dbg("_[_proppatch]_ need to set $propname to $propval on ([$path])  ![!! unhandled !!]!");
                push( @failed, { 'ns' => $ns, 'prop' => $propname, 'reqval' => $propval, 'code' => '405', 'msg' => 'Unsupported' } );
            }
        }

        foreach my $status_hr ( @succeeded, @failed ) {
            dbg( "_[_proppatch]_ status_hr = ", $status_hr );
            my $propstat_xml_element = $doc->createElement('D:propstat');
            my $prop_xml_element     = $doc->createElement('D:prop');
            my $propname_xml_element = $doc->createElement( $status_hr->{'prop'} );
            $propname_xml_element->setAttribute( 'xmlns:' . $prefixes{ $status_hr->{'ns'} }, $status_hr->{'ns'} );
            my $status_xml_element = $doc->createElement('D:status');
            $status_xml_element->appendText( 'HTTP/1.1 ' . $status_hr->{'code'} . ' ' . $status_hr->{'msg'} );
            $prop_xml_element->addChild($propname_xml_element);
            $propstat_xml_element->addChild($prop_xml_element);
            $propstat_xml_element->addChild($status_xml_element);
            $resp_xml_element->addChild($propstat_xml_element);
        }
        $resp->addChild($resp_xml_element);
    }

    $response->code(207);
    $response->message('Multi-Status');
    $response->header( 'Content-Type' => 'text/xml; charset="UTF-8"' );
    $doc->setDocumentElement($resp);
    $response->content( $doc->toString(1) );
    iolog(
        "\n<<<==[ Response ]===============================================<<<<\n",
        $doc->toString(1) . "\n",
        "<<<==[ End Response ]===========================================<<<<",
    );
    return;
}

# Handles wrapping PROPFIND and REPORT calls, does a lot of the shared decision making
sub _request_wrapper {    ##no critic(Subroutines::ProhibitExcessComplexity)
    my ( $self, $request, $response ) = @_;
    logfunc();

    my $path = $self->{'request_info'}{'fs_root'};

    dbg( "~[_request_wrapper]~ self = ", $self );

    # Be sure to keep the -e check after the virtual path checks.
    #     if ( ! $self->{'is_special_virtual_request'} || defined $self->{'request_info'}{'tags'}{'schedule-inbox'} ) {
    if ( !$self->{'request_info'}{'is_special_virtual_request'} ) {
        if ( $path =~ m/\.metadata$/ || $path =~ m/\.sharing$/ || !-e $path ) {
            dbg("~[_request_wrapper]~ : could not find ([$path]) ($!) or was a .hidden file, returning null");
            $response->code(404);
            $response->message('Not Found');
            goto QUICKEXIT;
        }
    }
    dbg("~[_request_wrapper]~ : Parsing request");
    my $parsed_request_hr = $self->_parse_request_payload( $request, $response );
    dbg( "~[_request_wrapper]~ : Parsed request is ", $parsed_request_hr );

    # If _parse_request_payload failed, we want to bubble up the $response generated there
    if ( !keys %{$parsed_request_hr} ) {
        return;
    }

    dbg("~[_request_wrapper]~ : path was ok and payload parsed ok; starting the response building now.");

    my $depth = $request->header('Depth') || 0;

    my $reqtype = $parsed_request_hr->{'reqtype'};
    my @hrefs   = @{ $parsed_request_hr->{'hrefs'} } if defined $parsed_request_hr->{'hrefs'};    # these hrefs are ones provided in the XML of the request, if any

    # If someone tries directory traversal in a href in the xml payload, detect it and stop processing
    foreach my $href (@hrefs) {
        dbg("-[_request_wrapper]- : raw href ([$href])");
        $href = decode_utf8( URI::Escape::uri_unescape($href) );
        dbg("-[_request_wrapper]- : escaped href ([$href])");
        if ( $href =~ m/\/\.\.\// ) {
            dbg("-[_request_wrapper]- : ![Directory traversal detected in href from XML payload]! ([$href])");
            $response->code(403);
            $response->message('Invalid Rquest');
            goto QUICKEXIT;
        }
    }

    dbg("-[_request_wrapper]- : depth = $depth");
    my @paths;
    dbg("-[_request_wrapper]- : self root vs path is ([$self->{'auth_user_caldav_root'}]) vs ([$path])");

    # If Depth header is 0, we only want to return properties for the specifically requested path ( /something/ )
    # If Depth header is 1, we want to return properties for all the immediate children of the path, but not the path itself ( ./cal/ ./cal2/ ./addybook/ etc inside of /something/ )
    # If the request is a calendar-multiget type and the request defined paths, use just those paths/hrefs, don't go searching the directory for more
    # If Depth header is 1 and is to a /calendars/$principal/ , we want to add our virtual urls, .inbox, .outbox and .freebusy . This has to avoid any actual path checks, as they do not really exist.
    dbg( "-[_request_wrapper]- : HREFS before checking depth is:", \@hrefs );

    if ( defined $depth and $depth == 1 and not( $reqtype eq 'calendar-multiget' and @hrefs ) and -d $path ) {

        # ensure path ends in a /
        $path .= '/' unless $path =~ m{/$};

        dbg("-[_request_wrapper]- : handling possibility of multiple paths for depth=1");
        my @entries;
        if ( opendir my $dir_fh, $path ) {
            @entries = readdir $dir_fh;
            closedir $dir_fh;
        }
        dbg( "-[_request_wrapper]- : entries found by readdir on ([$path]) are: ", \@entries );

        @paths = map { $path . $_ } File::Spec->no_upwards(@entries);

        dbg("-[_request_wrapper]- : including request path, cause reasons.");
        push( @paths, $path );

        # Specifically remove the metadata file, no direct DAV actions should happen against this, but we keep it there for easy organization
        # Also remove delegation/sharing config and event attachment files
        @paths = grep { !/(\.metadata$|\.sharing$|\.freebusy\.json|\.availability|\-attachment\-|\.tmp|calendar\-proxy\-read|calendar\-proxy\-write$)/ } @paths;    # the proxy paths are virtual, will they be here ?

        my $max_file_num = 125000;                                                                                                                                  # 125K events in a single collection has been tested on as little as a 2 Core, 2GB Ram VM without crashing it (HB-6732).
        if ( length $ENV{'MAXFILEPERCOL'} ) {
            $max_file_num = int( $ENV{'MAXFILEPERCOL'} );
            dbg("-[_request_wrapper]- : Overriding default for max files per collection via config entry ~[cpdavd_max_files_per_collection]~ in ([/var/cpanel/cpanel.config]) to -[$max_file_num]-");
        }
        dbg("-[_request_wrapper]- : max number of files to be processed in a single request is currently $max_file_num");

        # In a scenario where a single collection might have a huge number of events, we try to protect the server a bit by setting a limit. The only
        # recourse is for the users to manually delete some of the event files, or configure /var/cpanel/cpanel.config by setting "cpdavd_max_files_per_collection" to the desired number,
        # assuming their server can handle it.
        if ( @paths > $max_file_num ) {
            dbg( "-[_request_wrapper]- : ![user " . $self->{'auth_user'} . " is requesting more than $max_file_num events (" . int(@paths) . "), returning error]!" );
            $response->code(413);
            $response->message('Payload Too Large');
            goto QUICKEXIT;
        }

        my @final_paths;
        foreach my $base_path (@paths) {
            if ( $self->check_read_access($base_path) ) {
                push( @final_paths, $base_path );
                dbg("-[_request_wrapper]- : adding ([$base_path]) to path list because the current auth_user has read permission for it");
            }
            else {
                dbg("-[_request_wrapper]- : removing ([$base_path]) from path list because the current auth_user does not have read permission for it");
            }
        }
        @paths = @final_paths;
        dbg( "-[_request_wrapper]- : filtered out metadata, sharing and attachment files from paths: ", \@paths );
    }
    else {
        if ( !@hrefs ) {
            dbg( "-[_request_wrapper]- : Request with no HREFS, adding path ([$path]) to ", \@paths );
            @paths = ($path);
        }
    }

    dbg("-[_request_wrapper]- : Continuing request with the following paths : ([@paths])");

    if ( $reqtype eq 'calendar-multiget' || $reqtype eq 'addressbook-multiget' ) {
        dbg("-[_request_wrapper]- : since this request is a $reqtype , we will parse the hrefs and add them to paths");

        #         if( $reqtype eq 'addressbook-multiget' && @hrefs ) {
        if (@hrefs) {
            dbg("-[_request_wrapper]- : client specified href resources it wants information on, so ignoring the other stuff and just returning info on ([@hrefs])");
            @paths = ();
        }
        for my $href (@hrefs) {
            dbg("-[_request_wrapper]- : href ([$href])");

            if ( $self->{'request_info'}{'is_special_virtual_request'} ) {

                # Strip the virtual path info
                $href =~ s/$self->{'request_info'}{'uri_raw'}//;
                dbg("-[_request_wrapper]- : after stripping virtual path info we are left with $href");
                my $real_full_path = $self->{'request_info'}{'fs_root'} . $href;
                dbg("-[_request_wrapper]- : and now we have $real_full_path");
                push( @paths, $real_full_path );
            }
            else {
                # Convert URLs like /calendars/fun%40cptech1.test/calendar/369DA732-5464-47BA-ACBF-A92F55F51A7E.ics to it's actual file location on disk
                # also needs to cover case where the URL is for a shared resource
                dbg( "-[_request_wrapper]- : Need to convert ([$href]) to its actual path on disk", $self );

                #                 my $real_full_path = $self->{'auth_user_caldav_root'} . $href;
                my @href_parts     = split( /\//, $href );
                my $last_href_part = pop(@href_parts);

                dbg("-[_request_wrapper]- : href is ([$href]) , request_info fs_root is ([$self->{'request_info'}{'fs_root'}])");
                my $real_full_path = $self->{'request_info'}{'fs_root'};
                if ( -e $self->{'request_info'}{'fs_root'} . $last_href_part ) {
                    dbg("-[_request_wrapper]- : $self->{'request_info'}{'fs_root'} $last_href_part exists so using that");
                    $real_full_path = $self->{'request_info'}{'fs_root'} . $last_href_part;
                }

                # Fix encoded %40, as we use literal @ on the fs
                $real_full_path =~ s/\%40/\@/;
                dbg("-[_request_wrapper]- : ################## not a virtual path, so using $real_full_path");
                push( @paths, $real_full_path );
            }
        }
    }

    # https://datatracker.ietf.org/doc/rfc6578/
    # This is a REPORT query and is quite complicated.
    #     elsif ( $reqtype eq 'sync-collection' && $reqinfo =~ m/^sync\-/ ) {
    #         dbg("PROCESSING $reqinfo , \Qreqprops:", \@reqprops);
    #         for my $reqprop (@reqprops) {
    #             dbg( "FURTHER PROCESSING ", $reqprop );
    #             my ( $ns, $name ) = @$reqprop;
    #             dbg( "ABOUT TO GET TO IT", $prop, $ns, $name );
    #             my ( $ok_or_nf, $prop_element ) = $self->_process_property( $prop, $ns, $name, $request, $response, $reqprop->[0] );
    #             if ( $ok_or_nf == 1 ) {
    #                 $okprops->addChild($prop_element);
    #             }
    #             else {
    #                 $nfprops->addChild($prop_element);
    #             }
    #         }
    #
    #     }

    # This is for refining content processed from urls like /principals/user@dom.tld/calendars/
    # If we have a principal request for /principals/user@dom.tld/calendars/ remove paths for things that are not calendars
    # If we have a principal request for /principals/user@dom.tld/addressbooks/ remove paths for things that are not addressbooks
    if ( defined $self->{'request_info'}{'realm'} && defined $self->{'special_virtual_subpath'} && ( length( $self->{'special_virtual_subpath'} ) > 1 ) && $self->{'request_info'}{'realm'} eq 'principals' ) {
        for ( my $i = 0; $i < scalar @paths; $i++ ) {
            my $resource_type = $self->_get_metadata_property( $paths[$i], 'type' );
            dbg("-[_request_wrapper]- : resource type for ([$paths[$i]]) is $resource_type");

            if ( $resource_type ne 'VCALENDAR' && $self->{'special_virtual_subpath'} =~ m/calendars/ ) {
                dbg("-[_request_wrapper]- : removing ([$paths[$i]])");
                splice @paths, $i, 1;
                $i--;

            }
            elsif ( $resource_type ne 'VADDRESSBOOK' && $self->{'special_virtual_subpath'} =~ m/addressbooks/ ) {
                dbg("-[_request_wrapper]- : removing ([$paths[$i]])");
                splice @paths, $i, 1;
                $i--;
            }
        }
    }

    # We also need to add calendars that are shared to the principal user by other users and add them to the list alongside the principal's own calendars
    # If a specific collection is requested, ignore shared collections
    if ( length( $self->{'request_info'}{'principal_user'} ) && defined( $request->header('Depth') ) && $request->header('Depth') == 1 && !length( $self->{'request_info'}{'collection'} ) ) {
        my $sharing_hr = $self->load_sharing();
        dbg( "####################################### sharing_hr: ", $sharing_hr );
        foreach my $caluser ( keys %{$sharing_hr} ) {
            foreach my $shared_cal ( keys %{ $sharing_hr->{$caluser} } ) {
                if ( defined( $sharing_hr->{$caluser}{$shared_cal}{ $self->{'request_info'}{'principal_user'} } ) ) {
                    dbg("-[_request_wrapper]- : found user $caluser sharing $shared_cal with principal user, perms $sharing_hr->{$caluser}{$shared_cal}{$self->{'request_info'}{'principal_user'}}");

                    # Add the path to the shared calendar to @paths
                    push( @paths, $self->{'acct_homedir'} . '/.caldav/' . $caluser . '/' . $shared_cal . '/' );
                }
            }
        }
    }

    dbg("-[_request_wrapper]- : paths after including any shared collections : ([@paths])");

    # This is for refining content processed from urls like /calendars/user@dom.tld/*
    # If we have a request for /calendars/user@dom.tld/ remove paths for things that are not calendars
    # The length check on special_virtual_subpath is critical for a literal /calendars/user@dom.tld/ request to succeed
    if ( defined $self->{'request_info'}{'realm'} && $self->{'request_info'}{'realm'} eq 'calendars' && length( $self->{'request_info'}{'uri_decoded_safe'} ) > 11 ) {    # "/calendars/" == 11 chars
        dbg("-[_request_wrapper]- : handling special virtual request for /calendars/ with at least a principal user");
        for ( my $i = 0; $i < scalar @paths; $i++ ) {
            if ( -d $paths[$i] ) {

                # Don't remove paths for something like /home/user/.caldav/user@dom.tld/ . While it's in the calendar realm, it won't have metadata specifying that it's a VCALENDAR
                if ( $paths[$i] !~ m/\/[^\/]+\@[^\/]+\/?$/ ) {
                    my $resource_type = $self->_get_metadata_property( $paths[$i], 'type' );
                    dbg("-[_request_wrapper]- : resource type for ([$paths[$i]]) is $resource_type");
                    if ( $resource_type ne 'VCALENDAR' ) {
                        dbg("-[_request_wrapper]- : removing ([$paths[$i]])");
                        splice @paths, $i, 1;
                        $i--;
                    }
                }
            }
        }
    }

    # Same as above but for addressbooks
    if ( defined $self->{'request_info'}{'realm'} && $self->{'request_info'}{'realm'} eq 'addressbooks' && length( $self->{'request_info'}{'uri_decoded_safe'} ) > 14 ) {    # "/addressbooks/" == 14 chars
        dbg("-[_request_wrapper]- : handling special virtual request for /addressbooks/ with at least a principal user");
        for ( my $i = 0; $i < scalar @paths; $i++ ) {
            if ( -d $paths[$i] ) {

                # Don't remove paths for something like /home/user/.caldav/user@dom.tld/ . While it's in the calendar realm, it won't have metadata specifying that it's a VCALENDAR
                if ( $paths[$i] !~ m/\/[^\/]+\@[^\/]+\/?$/ ) {
                    my $resource_type = $self->_get_metadata_property( $paths[$i], 'type' );
                    dbg("-[_request_wrapper]- : resource type for ([$paths[$i]]) is $resource_type");
                    if ( length $resource_type && ( $resource_type ne 'VADDRESSBOOK' and $resource_type ne 'addressbook' ) ) {
                        dbg("-[_request_wrapper]- : resource_type is -[$resource_type]- , but we are looking at addresbooks, so removing ([$paths[$i]])");
                        splice @paths, $i, 1;
                        $i--;
                    }
                }
            }
        }
    }

    # If this is to /calendars/princi@p.al/ explicitly and Depth=1, add the inbox, outbox and freebusy paths for the principal to the paths to get properties from.
    # Note that these are virtual paths so any fs checks will fail, so tread carefully.
    if ( defined $request->header('Depth') && $request->header('Depth') == 1 && defined $self->{'request_info'}{'realm'} && $self->{'request_info'}{'realm'} eq 'calendars' && length $self->{'request_info'}{'principal_user'} && defined $self->{'request_info'}{'special_virtual_subpath'} && $self->{'request_info'}{'special_virtual_subpath'} eq '/' ) {

        # dbg("-[_request_wrapper]- : adding .inbox|.outbox|.freebusy to paths");
        push( @paths, $self->{'acct_homedir'} . '/.caldav/' . $self->{'request_info'}{'principal_user'} . '/.inbox' );
        push( @paths, $self->{'acct_homedir'} . '/.caldav/' . $self->{'request_info'}{'principal_user'} . '/.outbox' );
        push( @paths, $self->{'acct_homedir'} . '/.caldav/' . $self->{'request_info'}{'principal_user'} . '/.freebusy' );
    }

    # If this is to /principals/princi@p.al/ explicitly and Depth=1, add the calendar-proxy-read and calendar-proxy-write paths
    #     dbg("-[_request_wrapper]- : dump of all the things : ", $request->header('Depth'), $self->{'request_info'}{'realm'}, $self->{'request_info'}{'principal_user'}, $self->{'request_info'}{'special_virtual_subpath'});
    if ( defined $request->header('Depth') && $request->header('Depth') == 1 && defined $self->{'request_info'}{'realm'} && $self->{'request_info'}{'realm'} eq 'principals' && length $self->{'request_info'}{'principal_user'} && defined $self->{'request_info'}{'special_virtual_subpath'} && $self->{'request_info'}{'special_virtual_subpath'} eq '/' ) {
        dbg("-[_request_wrapper]- : adding calendar-proxy-read and calendar-proxy-write to paths");
        push( @paths, $self->{'acct_homedir'} . '/.caldav/' . $self->{'request_info'}{'principal_user'} . '/calendar-proxy-read' );
        push( @paths, $self->{'acct_homedir'} . '/.caldav/' . $self->{'request_info'}{'principal_user'} . '/calendar-proxy-write' );
    }

    # Remove any duplicated paths, usually resulting from hrefs in the payload + depth:1 header finding the same files
    my %seen_paths;
    @paths = grep !$seen_paths{$_}++, @paths;

    # Create doc early so we can pass it on to the handlers to use if they need it.
    # As seen several times, if you mix two document objects they will show random corruption, for reasons
    # not fully understood. This is just a means of working around that.
    my $doc = XML::LibXML::Document->new( '1.0', 'UTF-8' );

    # Shared logic done, send the requests to their appropriate handlers
    my $xml_responses_ar;
    if ( $parsed_request_hr->{'method'} eq 'REPORT' ) {
        $xml_responses_ar = $self->_report( $request, $response, $parsed_request_hr, \@paths, \@hrefs, \$doc );
    }
    elsif ( $parsed_request_hr->{'method'} eq 'PROPFIND' ) {
        $xml_responses_ar = $self->_propfind( $request, $response, $parsed_request_hr, \@paths, \@hrefs, \$doc );
    }
    my @responses_text = map { $_->toString(1) } @{$xml_responses_ar};
    dbg("~[_request_wrapper]~ : responses from handler :\n#[@responses_text]#") if @responses_text;

    # Before we had support for multistatus, we always would return a 200. once support was added, we split it off
    # to return a 207 if there were multiple properties involved, but still 200 when there was just one. It is however
    # perfectly find to always respond with a 207 even for a single property, as the response code is still nestled in the
    # multistatus reply,

    # Some requests should not respond with multistatus, so we return those directly. Add any of these request types here
    my @direct_response_reqtypes = qw/principal-search-property-set/;

    if ( grep /^\Q$reqtype\E$/, @direct_response_reqtypes ) {
        dbg("~[_request_wrapper]~ : sending direct request response for -[$reqtype]-");
        $response->code(200);
        $response->message('OK');
        $response->header( 'Content-Type' => 'text/xml; charset="UTF-8"' );
        if (@$xml_responses_ar) {
            $doc->setDocumentElement( @{$xml_responses_ar} );
        }
        else {
            dbg("~[_request_wrapper]~ : our XML response will be empty due to lack of results");
        }
    }
    else {
        dbg("~[_request_wrapper]~ : sending multistatus request response for -[$reqtype]-");
        $response->code(207);
        $response->message('Multi-Status');
        $response->header( 'Content-Type' => 'text/xml; charset="UTF-8"' );
        my $wrapper_element = $doc->createElement('D:multistatus');

        # We define all of our known prefixes for each request so they are readily available to refer to in responses without having to keep track of
        # which namespace is needed for each response
        foreach my $namespace ( keys %prefixes ) {
            $wrapper_element->setAttribute( 'xmlns:' . $prefixes{$namespace}, $namespace );
        }

        $doc->setDocumentElement($wrapper_element);
        foreach my $resp ( @{$xml_responses_ar} ) {
            $wrapper_element->addChild($resp);
        }
    }

    dbg( "~[_request_wrapper]~ : REACHED THE END OF REQUEST PROCESSING. Responding with:\n>>>==>[ Request Response ]>=========================================>>>\n*[" . $doc->toString(1) . "]*\n>>>==>[ End Request Response ]>=====================================>>>\n" );
    iolog(
        "\n<<<==[ Response ]===============================================<<<<\n",
        $doc->toString(1) . "\n",
        "<<<==[ End Response ]===========================================<<<<",
    );
    $response->content( $doc->toString(1) );
    return;    # We've modified $response directly, so just return here
}

# This sub takes the <prop> elements from the <property-search> element and returns what matches the criteria in $search_data_hr . It does not process <prop>s outside of <property-search> .
sub _apply_search_filters {
    my ( $self, $request, $response, $search_data_hr, $principal ) = @_;
    logfunc();
    if ( !$search_data_hr ) { $search_data_hr = $self->{'search_data_hr'}; }    # temporary until final design is figured out

    dbg( "-[_apply_search_filters]- : self and search_data_hr for -[$principal]- are", $self, $search_data_hr );
    $self->{'search_principal'} = $principal;                                   # Allows this to be used by _process_property() handlers

    # Get a parser so we can get the plain text values of the properties back from the generated property XML. This should work for simple properties, but complex ones... not so much.
    # We'll probably only allow a handful of simple properties to be searched, at least until we find the need to accomodate more complex ones.
    my $parser            = XML::LibXML->new;
    my $namespace_context = XML::LibXML::XPathContext->new();
    foreach my $prefix ( keys %prefixes_by_long_name ) {
        $namespace_context->registerNs( $prefix, $prefixes_by_long_name{$prefix} );
    }

    # my @returned_xml;

    # Search properties are additive with the allof, so multiple properties must ALL match before we consider it a "hit".
    # When search type is anyof, only one match of all given search properties needs to match.
    my $ruled_out             = 0;
    my $matched_at_least_one  = 0;
    my $search_inclusion_type = $self->{'search_query_type'};
    dbg("-[_apply_search_filters]- : for each property, the exclusion/inclusion type is $search_inclusion_type");
    foreach my $prop ( keys %{$search_data_hr} ) {
        dbg("-[_apply_search_filters]- : searching for prop -[$prop]-");
        if ( $search_inclusion_type eq 'allof' && $ruled_out ) {
            dbg("-[_apply_search_filters]- : ruled out by previous property not matching and inclusion type is allof");
            return 0;
        }
        elsif ( $search_inclusion_type eq 'anyof' && $matched_at_least_one ) {
            dbg("-[_apply_search_filters]- : matched at least one property and inclusion type is anyof, shortcutting out");
            return $matched_at_least_one;
        }

        my $prop_xml_string;
        my $ns = $search_data_hr->{$prop}{'ns'};
        dbg("-[_apply_search_filters]- : ns = $ns, prop = $prop");
        my $property_result = $self->_process_property( $prop_xml_string, $ns, $prop, $request, $response, '' );
        dbg( "-[_apply_search_filters]- : property_result is ", $property_result );

        # XML::LibXML is very strict, and without knowing both the namespace and the shortcut used, if any, to refer to it, we can't just call ->localname to find the value.
        # So in this particular case, we use a regex to get the text value. Attempts to do this better are left commented out below, maybe someone else can find a better solution.
        # Note that this will extract user@dom.tld from stuff like:
        #  <D:displayname>user@dom.tld</D:displayname>
        #  as well as
        #   <CS:email-address-set><CS:email-address>user@dom.tld</CS:email-address></CS:email-address-set>
        my $prop_val;
        if ( $property_result =~ /<[^>]+>([^<]+)<\/[^>]+>/ ) {
            $prop_val = $1;
            dbg("-[_apply_search_filters]- : extracted text in property_result: ([$prop_val])");
        }
        else {
            dbg("-[_apply_search_filters]- : ![could not find text in property_result]! !!");

            # In this situation, we currently assume that it was an unsupported property, like email-address directly (rather than email-address-set, which includes it).
            # We don't want to tank all matches just because we donn't support whatever they might be looking for
            next;
        }

        # Trying to force the known NS on the property doesn't seem to work, LibXML still complains.
        # $property_result =~ s/<(\/)?(\w+):([^>]+)>/<$1xmlns='$ns' $3>/g;
        # dbg("-[_apply_search_filters]- : Namespace override version : $property_result");
        # my $property_xml_doc = $parser->parse_string($property_result);
        # dbg("-[_apply_search_filters]- : property_xml_doc : ", $property_xml_doc);
        # $property_xml_doc->findnodes('/root')->[0]->setNamespace( $prefixes{$ns}, $ns );
        # dbg("-[_apply_search_filters]- : property_xml_doc after setting ns : ", $property_xml_doc);
        # my $element = $property_xml_doc->findnodes("//*[namespace-uri() = '$ns' and local-name() = '$prop']")->[0];
        # dbg("-[_apply_search_filters]- : element is", $element);
        # if ($element) {
        #     my $text_content = $element->textContent;
        #     dbg("-[_apply_search_filters]- : Text Content: $text_content");
        # } else {
        #     dbg("-[_apply_search_filters]- : Element $ns$prop not found.");
        # }
        # my $prop_val2 = $property_xml_doc->localname;
        # dbg("-[_apply_search_filters]- : parsed prop_val : $prop_val2");

        # match-type : equals, contains , starts-with , ends-with and not- prefixing those as well, like not-starts-with, tho we probably don't need that in practice
        my $match_text = $search_data_hr->{$prop}{'match-text'};
        my $match_type = $search_data_hr->{$prop}{'match-type'};
        my $regex;
        my $negated = ( $match_type =~ /^not-/ );
        $match_type =~ s/^not-//;
        if ( $match_type eq 'equals' ) {
            $regex = qr/^\Q$match_text\E$/;
        }
        elsif ( $match_type eq "contains" ) {
            $regex = qr/\Q$match_text/;
        }
        elsif ( $match_type eq "starts-with" ) {
            $regex = qr/^\Q$match_text/;
        }
        elsif ( $match_type eq "ends-with" ) {
            $regex = qr/\Q$match_text\E$/;
        }
        else {
            dbg("-[_apply_search_filters]- : ![Unsupported search type]! : -[$match_type]-");
            next;    # Currently running with the assumption that an unsupported search/match type should not count against any other matches, rather than causing it to negate everything
        }
        if ( ( $negated && $prop_val !~ $regex ) || ( !$negated && $prop_val =~ $regex ) ) {
            dbg("-[_apply_search_filters]- : Match found in $prop_val ($negated) ($regex)");

            # dbg("-[_apply_search_filters]- : pushing #[$property_result]# to return array");
            $matched_at_least_one++;

            # push(@returned_xml, $property_result);
        }
        else {
            dbg("-[_apply_search_filters]- : No match found for $prop_val ($negated) ($regex)");
            $ruled_out++;
        }
    }

    if ( $matched_at_least_one && $search_inclusion_type eq 'anyof' ) {

        # Leave for debugging for now
        dbg("-[_apply_search_filters]- : anyof search returning : $matched_at_least_one");
    }
    return $matched_at_least_one;
}

# If no args passed, will list all principals available to the system account
# If a string is passed, it will return the first time an exact match is found, or empty
sub _get_principals {
    my ( $self, $exact_match ) = @_;
    logfunc();
    if ( length $exact_match ) {
        dbg("-[_get_principals]- : Looking for exact principal match -[$exact_match]-");
    }
    else {
        dbg("-[_get_principals]- : Listing all pricipals known to current user");
    }
    my @principals;

    # Get a list of all principals and include all known data about them used by REPORT queries
    my $principals_base_dir = $self->{'acct_homedir'} . '/.caldav/';
    if ( !-d $principals_base_dir ) {
        dbg("-[_get_principals]- : ([$principals_base_dir]) ![is not a directory ?]!");
        return [];
    }
    if ( opendir( my $princ_dir_fh, $principals_base_dir ) ) {
        while ( my $thing = readdir($princ_dir_fh) ) {
            next if $thing =~ m/^\./;
            if ( $thing =~ m/\@/ ) {
                my ( $luser, $ldom ) = split( '@', $thing );
                dbg("-[_get_principals]- : checking whether mail dir exists for $thing");
                if ( $self->_mail_dir_exists( $ldom, $luser ) ) {
                    if ( $exact_match && $exact_match eq $thing ) {    # If we find the exact user we were looking for, shortcut out of here with it
                        return [$exact_match];
                    }
                    push( @principals, $thing );
                }
            }
            elsif ( $thing eq $self->{'sys_user'} ) {    # If this is for the system user of the account..
                if ( $exact_match && $exact_match eq $thing ) {    # If we find the exact user we were looking for, shortcut out of here with it
                    return [$exact_match];
                }
                push( @principals, $thing );
            }
        }
        closedir($princ_dir_fh);
    }
    if ($exact_match) { return undef; }    # If we were asked to find a particular user and ended up here, it means we did not, so return empty handed
    return \@principals;
}

# Currently _report is duplicating _propfind almost entirely, but they should diverge over time as support for more _report queries is added
sub _report {    ##no critic(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)
    my ( $self, $request, $response, $parsed_request_hr, $paths_hr, $hrefs_hr, $doc_sr ) = @_;
    logfunc();

    my @paths    = @{$paths_hr};
    my @hrefs    = @{$hrefs_hr};
    my $depth    = $request->header('Depth');
    my $reqinfo  = $parsed_request_hr->{'reqinfo'};
    my $reqtype  = $parsed_request_hr->{'reqtype'};
    my @reqprops = @{ $parsed_request_hr->{'reqprops'} } if defined $parsed_request_hr->{'reqprops'};

    dbg( "-[_report]- : reqtype is $reqtype , reqinfo is $reqinfo, reqprops are ", @reqprops );
    dbg( "-[_report]- : href paths are : ",                                        \@hrefs );
    dbg( "-[_report]- : Starting processing of each path in : ",                   \@paths );

    # Create the XML doc that will hold the <response> </response> for each property
    my $doc = $$doc_sr;
    my @xml_responses;

    # temp location to hold principal-search-property-set info
    my %principal_search_properties;
    $principal_search_properties{'displayname'}{'description'}               = 'Display Name';
    $principal_search_properties{'displayname'}{'ns'}                        = 'DAV:';
    $principal_search_properties{'email-address-set'}{'description'}         = 'Email Addresses';
    $principal_search_properties{'email-address-set'}{'ns'}                  = 'http://calendarserver.org/ns/';
    $principal_search_properties{'calendar-user-address-set'}{'description'} = 'Calendar User Address Set';
    $principal_search_properties{'calendar-user-address-set'}{'ns'}          = 'urn:ietf:params:xml:ns:caldav';
    $principal_search_properties{'calendar-user-type'}{'description'}        = 'Calendar User Type';              # INDIVIDUAL,GROUP,RESOURCE,ROOM,UNKNOWN,X-custom https://datatracker.ietf.org/doc/html/rfc5545#section-3.2.3
    $principal_search_properties{'calendar-user-type'}{'ns'}                 = 'urn:ietf:params:xml:ns:caldav';

    # Handle report requests that don't involve @paths up here and return early

    # Consider add support for calendarserver-principal-search, which is only found in CCS , example payload:
    # <?xml version="1.0" encoding="UTF-8"?>
    # <C:calendarserver-principal-search xmlns:C="http://calendarserver.org/ns/" context="location">
    #   <C:search-token>awda</C:search-token>
    #   <A:prop xmlns:A="DAV:">
    #     <A:displayname/>
    #     <C:record-type/>
    #     <A:principal-URL/>
    #     <B:calendar-user-address-set xmlns:B="urn:ietf:params:xml:ns:caldav"/>
    #     <C:email-address-set/>
    #     <C:first-name/>
    #     <B:calendar-user-type xmlns:B="urn:ietf:params:xml:ns:caldav"/>
    #     <C:last-name/>
    #   </A:prop>
    # </C:calendarserver-principal-search>

    if ( $reqtype eq 'principal-search-property-set' ) {
        dbg("-[_report]- : processing $reqtype");
        my $principal_search_properties_doc = $doc->createElementNS( 'DAV:', 'principal-search-property-set' );
        foreach my $prop ( keys %principal_search_properties ) {
            my $psp_element       = $doc->createElement('principal-search-property');
            my $prop_element      = $doc->createElement('prop');
            my $prop_name_element = $doc->createElementNS( $principal_search_properties{$prop}{'ns'}, $prop );
            my $prop_desc_element = $doc->createElement('description');
            $prop_desc_element->setAttribute( 'xml:lang', 'en' );
            $prop_desc_element->appendText( $principal_search_properties{$prop}{'description'} );
            $prop_element->addChild($prop_name_element);
            $psp_element->addChild($prop_element);
            $psp_element->addChild($prop_desc_element);
            $principal_search_properties_doc->addChild($psp_element);
        }
        push( @xml_responses, $principal_search_properties_doc );
        return \@xml_responses;
    }
    elsif ( $reqtype eq 'principal-property-search' ) {
        dbg("-[_report]- reqtype is principal-property-search");

        # HB-7215 - medium - See http://webdav.org/specs/rfc3744.html for apply-to-principal-collection-set , only used by Evolution so far that I've found
        #        From RFC:
        #          By default, the report searches all members (at any depth) of the collection identified by the Request-URI. If DAV:apply-to-principal-collection-set is
        #          specified in the request body, the request is applied instead to each collection identified by the DAV:principal-collection-set property of the resource
        #          identified by the Request-URI.

        if ( $reqinfo eq 'apply-to-principal-collection-set' ) {
            dbg("-[_report]- ![reqinfo is apply-to-principal-collection-set , and needs to be handled slightly differently than property-search , which is likely the next element in the request]!");
        }
        elsif ( $reqinfo eq 'property-search' ) {
            dbg("-[_report]- processing property-search");

            # Get list of principals accessible to the authd user, filtered by the search_data_hr
            # Each remaining principal gets a <response>
            # Each <response> has an href pointing to the principal /principals/user@dom.tld/
            # Each <response> has a <propstat><prop> that includes all of the reqprops relevent to the principal
            # Each property is run through _process_property to get result, and all that is put together for the response.
            my $search_data_hr = $parsed_request_hr->{'search_data'};

            # Save this in self to make it accessible from anywhere
            $self->{'search_data_hr'} = $search_data_hr;
            $self->{'is_a_search'}    = 1;

            dbg( "-[_report]- search_data_hr is ", $search_data_hr );
            my $principals_ar = $self->_get_principals();
            dbg( "-[_report]- all principals: ", $principals_ar );
            foreach my $principal ( @{$principals_ar} ) {

                my $matched_principal = $self->_apply_search_filters( $request, $response, $search_data_hr, $principal );
                if ( !$matched_principal ) {
                    dbg("-[_report]- : filtered out $principal");
                    next;
                }
                else {
                    dbg("-[_report]- : including $principal in results");
                }
                my $resp = $doc->createElement('D:response');
                $resp->appendTextChild( 'D:href' => '/principals/' . $principal . '/' );

                # Add <propstat><prop> , then loop through each repprops property and add to <prop>, then add all to $resp
                my $propstat_xml_element = $doc->createElement('D:propstat');
                my $prop_xml_element     = $doc->createElement('D:prop');

                dbg( "-[_report]- : reqprops = ", \@reqprops );
                foreach my $requested_prop (@reqprops) {
                    my $prop_xml_string;
                    my ( $ns, $propname ) = @$requested_prop;

                    # get the xml for the property and append it to $prop_xml_element
                    dbg("-[_report]- : ns = $ns, propname = $propname");
                    my $property_result = $self->_process_property( $prop_xml_string, $ns, $propname, $request, $response, '' );
                    $prop_xml_element->addChild($property_result);
                }
                $propstat_xml_element->addChild($prop_xml_element);
                my $stat = $doc->createElement('D:status');
                $stat->appendText('HTTP/1.1 200 OK');
                $propstat_xml_element->addChild($stat);
                $resp->addChild($propstat_xml_element);

                push( @xml_responses, $resp );
            }
        }
        elsif ( $reqinfo eq 'prop' ) {    # very similar to property-search, but returns all prinicipals. This request is possible but unlikely.
            dbg("-[_report]- : this is a direct prop request");

            # iterate through all principals and get requested properties
            my $principals_ar = $self->_get_principals();
            foreach my $principal ( @{$principals_ar} ) {
                dbg("-[_report]- : building props for $principal");
                my $resp = $doc->createElement('D:response');
                $resp->appendTextChild( 'D:href' => '/principals/' . $principal . '/' );
                my $propstat_xml_element = $doc->createElement('D:propstat');
                my $prop_xml_element     = $doc->createElement('D:prop');
                dbg( "-[_report]- : reqprops = ", \@reqprops );
                $self->{'is_a_search'}      = 1;
                $self->{'search_principal'} = $principal;

                foreach my $requested_prop (@reqprops) {
                    my $prop_xml_string;
                    my ( $ns, $propname ) = @$requested_prop;

                    # get the xml for the property and append it to $prop_xml_element
                    dbg("-[_report]- : ns = $ns, propname = $propname");
                    my $property_result = $self->_process_property( $prop_xml_string, $ns, $propname, $request, $response, '' );
                    $prop_xml_element->addChild($property_result);
                }
                $propstat_xml_element->addChild($prop_xml_element);
                my $stat = $doc->createElement('D:status');
                $stat->appendText('HTTP/1.1 200 OK');
                $propstat_xml_element->addChild($stat);
                $resp->addChild($propstat_xml_element);
                push( @xml_responses, $resp );
            }
        }
        return \@xml_responses;
    }

    for my $path ( sort @paths ) {
        if ( $self->check_read_access($path) ) {
            my ( $dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks ) = stat($path);

            # modified time is stringified human readable HTTP::Date style
            $mtime = HTTP::Date::time2str($mtime);

            # created time is ISO format
            # tidy up date format - isoz isn't exactly what we want, but it's easy to change.
            $ctime = HTTP::Date::time2isoz($ctime);
            $ctime =~ s/ /T/;
            $ctime =~ s/Z//;

            $size ||= '';
            dbg("-[_report]- : size of ([$path]) is $size");
            my $resp = $doc->createElement('D:response');
            my $href = $doc->createElement('D:href');

            my $display_path = '';

            # Reflecting the request path even with no hrefs and 1 element in @paths fails when the 1 path is a calendar and depth = 1, so we only do the deeper dive when depth = 1
            if ( @paths == 1 && !@hrefs && $self->{'request_info'}{'depth'} == 0 ) {
                dbg("-[_report]- : Only one path, reflecting the request ([$self->{'request_info'}{'uri_decoded_safe'}])");
                $display_path = $self->{'request_info'}{'uri_decoded_safe'};
            }
            else {
                my $encoded_path = File::Spec->catdir( map { uri_escape encode_utf8 $_} File::Spec->splitdir($path) );

                # Add back the trailing slash if it was in the original path
                if ( $path =~ m/\/$/ ) {
                    $encoded_path .= '/';
                }
                dbg("-[_report]- : calling _get_display_path on ([$encoded_path])");
                $display_path = $self->_get_display_path($encoded_path);
            }

            my $path_info_hr = $self->_parse_request_path($path);

            # Note - 'current_path_info' details are parsed from 'req_path', which relates to the current path ( be it direct or autogenerated from a depth=1 header ) and
            # is vital for the property processing handlers to function accurately.
            $self->{'current_path_info'} = $path_info_hr;

            dbg( "-[_report]- : GWARRRRR : display_path: ([$display_path]) path ([$path]) path_info_hr and self:", $path_info_hr, $self );

            $href->appendText($display_path);    # This is probably the href you are looking for, right after the initial <D:response> for REPORT
            my $huh       = $href->textContent();
            my $last_char = substr $href->textContent(), -1;

            if ( -d $path && ( substr $href->textContent(), -1 ) ne '/' ) {
                dbg("-[_report]- : adding a trailing slash because ([$path]) is a directory and it's last char ($last_char) is not / ($huh)");
                $href->appendText('/');
            }
            $resp->addChild($href);

            $self->{'mtime'}                         = $mtime;
            $self->{'size'}                          = $size;
            $self->{'ctime'}                         = $ctime;
            $self->{'display_path'}                  = $display_path;
            $self->{'current_path_info'}{'req_path'} = $path;           # Crucial for shared paths

            my $okprops = $doc->createElement('D:prop');
            my $nfprops = $doc->createElement('D:prop');
            my $prop;

            dbg("-[_report]- : handling reqtype($reqtype) , reqinfo($reqinfo) on path(([$path])) , display_path(([$display_path]))");

            # https://datatracker.ietf.org/doc/rfc6578/
            # if ( $reqtype eq 'sync-collection' ) {
            #     dbg("inside -[_report]- for sync-collection, currently not handled, but here's where we could add it");
            # }

            # Some REPORT queries have no $reqinfo, just a single $reqtype XML line
            if ( $self->{'request_info'}{'method'} eq 'REPORT' && !$reqinfo ) {
                dbg("-[_report]- : no reqinfo in this REPORT query");
                $self->_process_report( $request, $response, $reqtype, $parsed_request_hr );
            }

            elsif ( $reqinfo eq 'prop' || $reqinfo eq 'property' ) {
                $self->{'nf_iteration'} = 0;
                for my $reqprop (@reqprops) {
                    if ( ref $reqprop ne 'ARRAY' ) {
                        dbg("-[_report]- : ![\$reqprop was not an array, aborting due to unexpected data type.]!");
                        return;
                    }

                    dbg( "-[_report]- : iterating through reqprops, looking at the : ", $reqprop );

                    # Leaving this here for now. Currently we are handling subproperties within the lookup table code ref for each
                    # property. This makes sense as subproperties vary based on the properties they are under, such as "displayname" when
                    # iterating over users in a particular group.
                    #
                    # If a property has subproperties, we have to iterate through them and add them to the parent property
                    # if( ref $reqprop->[0] eq 'HASH' && defined( $reqprop->[0]->{'subprops'} ) ) {
                    #    dbg("-[_report]- : this property has sub properties..");
                    #    my $subprop_ns_and_name = $prefixes{$reqprop->[0]->{'parent_namespace'}} .':'. $reqprop->[0]->{'parent_name'};
                    #    dbg("-[_report]- : this property has sub properties.. $subprop_ns_and_name");
                    #    my $prop_with_sub_properties = $doc->createElement($subprop_ns_and_name);
                    #    foreach my $subprop_ar( @{$reqprop->[0]->{'subprops'}} ) {
                    #        dbg("-[_report]- : subprop is : ", $subprop_ar);
                    #        my($ns,$name) = @{$subprop_ar};
                    #        dbg("-[_report]- : need to process $ns : $prop as a subproperty of $reqprop->[0]->{'parent_name'}");
                    #        my ( $ok_or_nf, $subprop_element ) = $self->_process_property( $prop_with_sub_properties, $ns, $name, $request, $response, $reqprop->[0] );
                    #        if( $ok_or_nf == 1 ) {
                    #            $prop_with_sub_properties->addChild($subprop_element);
                    #        }
                    #    }
                    #    $okprops->addChild($prop_with_sub_properties);
                    # }

                    if ( ref $reqprop->[0] eq 'HASH' ) {
                        dbg("-[_report]- : need to wrap child props inside parent prop");

                        # If this is "much nested, such wow" property, we need to iterate a lot here..

                        foreach my $parent_prop ( @{$reqprop} ) {
                            dbg("-[_report]- : parent name = $parent_prop->{'parent_name'}");
                            dbg("-[_report]- : parent ns   = $parent_prop->{'parent_namespace'}");
                            my $name = $parent_prop->{'parent_name'};
                            my $ns   = $parent_prop->{'parent_namespace'};

                            if ( !exists $prefixes{$ns} ) {
                                dbg( "-[_report]- : ruhrohraggy, no $ns found in our known list:", \%prefixes );
                            }
                            dbg("-[_report]- : sending off request to _process_property ($ns,$name)");
                            my ( $ok_or_nf, $prop_element ) = $self->_process_property( $prop, $ns, $name, $request, $response, $reqprop->[0] );
                            if ( $ok_or_nf == 1 ) {
                                $okprops->addChild($prop_element);
                            }
                            else {
                                $nfprops->addChild($prop_element);
                            }
                        }
                    }
                    else {
                        dbg("-[_report]- : didn't find parent_name, assuming this is a straight-forward property");
                        my ( $ns, $name ) = @$reqprop;
                        dbg("-[_report]- : calling _process_property for /[$ns]/ , -[$name]-");
                        my ( $ok_or_nf, $prop_element ) = $self->_process_property( $prop, $ns, $name, $request, $response, '' );
                        $okprops->addChild($prop_element);
                        if ( $ok_or_nf == 1 ) {
                            $okprops->addChild($prop_element);
                        }
                        else {
                            $nfprops->addChild($prop_element);
                        }
                    }
                }
            }
            elsif ( $reqinfo eq 'propname' ) {
                $prop = $doc->createElement('D:creationdate');
                $okprops->addChild($prop);
                $prop = $doc->createElement('D:getcontentlength');
                $okprops->addChild($prop);
                $prop = $doc->createElement('D:getcontenttype');
                $okprops->addChild($prop);
                $prop = $doc->createElement('D:getlastmodified');
                $okprops->addChild($prop);
                $prop = $doc->createElement('D:resourcetype');
                $okprops->addChild($prop);
            }
            else {
                dbg("-[_report]- : Got unspecified reqinfo: $reqinfo, so building an allprop response for now");
                $prop = $doc->createElement('D:creationdate');
                $prop->appendText($ctime);
                $okprops->addChild($prop);
                $prop = $doc->createElement('D:getcontentlength');
                $prop->appendText($size);
                $okprops->addChild($prop);
                $prop = $doc->createElement('D:getcontenttype');

                if ( -d $path ) {
                    $prop->appendText('httpd/unix-directory');
                }
                else {
                    $prop->appendText('httpd/unix-file');
                }
                $okprops->addChild($prop);
                $prop = $doc->createElement('D:getlastmodified');
                $prop->appendText($mtime);
                $okprops->addChild($prop);
                do {
                    $prop = $doc->createElement('D:supportedlock');
                    for my $n (qw(exclusive shared)) {
                        my $lock = $doc->createElement('D:lockentry');

                        my $scope = $doc->createElement('D:lockscope');
                        my $attr  = $doc->createElement( 'D:' . $n );
                        $scope->addChild($attr);
                        $lock->addChild($scope);

                        my $type = $doc->createElement('D:locktype');
                        $attr = $doc->createElement('D:write');
                        $type->addChild($attr);
                        $lock->addChild($type);

                        $prop->addChild($lock);
                    }
                    $okprops->addChild($prop);
                };
                $prop = $doc->createElement('D:resourcetype');
                if ( -d $path ) {
                    my $col = $doc->createElement('D:collection');
                    $prop->addChild($col);
                }
                $okprops->addChild($prop);
            }

            if ( $okprops->hasChildNodes ) {
                my $propstat = $doc->createElement('D:propstat');
                $propstat->addChild($okprops);
                my $stat = $doc->createElement('D:status');
                $stat->appendText('HTTP/1.1 200 OK');
                $propstat->addChild($stat);
                $resp->addChild($propstat);
            }
            else {
                dbg("-[_report]- : okprops does NOT have child nodes");
            }

            # Handle unsupported properties
            if ( $nfprops->hasChildNodes ) {
                dbg("-[_report]- : nfprops has child nodes, building 404 status reponses..");
                my $propstat = $doc->createElement('D:propstat');
                $propstat->addChild($nfprops);
                my $stat = $doc->createElement('D:status');
                $stat->appendText('HTTP/1.1 404 Not Found');
                $propstat->addChild($stat);
                $resp->addChild($propstat);
            }
            else {
                dbg("-[_report]- : nfprops does NOT have child nodes");
            }

            push( @xml_responses, $resp );
        }

        # If no read permission, we ignore it, rather than disclosing it exists but they aren't allowed to do anything with it
    }

    return \@xml_responses;
}

sub _propfind {    ##no critic(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)
    my ( $self, $request, $response, $parsed_request_hr, $paths_hr, $hrefs_hr, $doc_sr ) = @_;
    logfunc();

    my @paths = @{$paths_hr};
    my @hrefs = @{$hrefs_hr};

    my $reqinfo  = $parsed_request_hr->{'reqinfo'};
    my $reqtype  = $parsed_request_hr->{'reqtype'};
    my @reqprops = @{ $parsed_request_hr->{'reqprops'} } if defined $parsed_request_hr->{'reqprops'};

    dbg("-[_propfind]- : reqtype is $reqtype");

    dbg( "-[_propfind]- : Starting processing of each path in : ", \@paths );

    # Create the XML doc that will hold the <response> </response> for each property
    my $doc = $$doc_sr;
    my @xml_responses;
    for my $path ( sort @paths ) {

        # Some virtual paths are free to be seen by any authenticated user

        next if !$self->check_read_access($path);    # If no read permission, we ignore it, rather than disclosing it exists but they aren't allowed to do anything with it

        my $path_info_hr = $self->_parse_request_path($path);

        # For virtual paths, no sense in trying to stat()
        unless ( $path_info_hr->{'is_special_virtual_request'} ) {
            @$self{qw{size mtime_stat ctime_stat}} = ( ( stat($path) )[ 7, 9, 10 ] );
        }

        # modified time is stringified human readable HTTP::Date style.
        # NOTE that on undef, it falls back to now(),
        # which is what virtual paths will be using.
        $self->{'mtime'} = HTTP::Date::time2str( $self->{'mtime_stat'} );

        # created time is ISO format
        # tidy up date format - isoz isn't exactly what we want, but it's easy to change.
        $self->{'ctime'} = HTTP::Date::time2isoz( $self->{'ctime_stat'} );
        $self->{'ctime'} =~ tr/ /T/;
        $self->{'ctime'} =~ tr/Z//;

        $self->{'size'} ||= '';
        dbg("-[_propfind]- : size of ([$path]) is $self->{'size'}");

        my $resp = $doc->createElement('D:response');
        my $href = $doc->createElement('D:href');

        dbg("-[_propfind]- : paths is ([@paths]) ");

        my $encoded_path = File::Spec->catdir( map { uri_escape encode_utf8 $_} File::Spec->splitdir($path) );
        dbg("-[_propfind]- : calling _get_display_path on ([$encoded_path])");
        my $display_path = $self->_get_display_path($encoded_path);

        # Note - 'current_path_info' details are parsed from 'req_path', which relates to the current path ( be it direct or autogenerated from a depth=1 header ) and
        # is vital for the property processing handlers to function accurately.
        $self->{'current_path_info'} = $path_info_hr;

        dbg( "-[_propfind]- : GWARRRRR : display_path: ([$display_path]) path ([$path]) path_info_hr and self:", $path_info_hr, $self );

        $href->appendText($display_path);    # This is probably the href you are looking for, right after the initial <D:response> for PROPFIND
        my $huh       = $href->textContent();
        my $last_char = substr $href->textContent(), -1;

        if ( -d $path && ( substr $href->textContent(), -1 ) ne '/' ) {
            dbg("-[_propfind]- : adding a trailing slash because ([$path]) is a directory and it's last char ($last_char) is not / ($huh)");
            $href->appendText('/');
        }
        $resp->addChild($href);

        $self->{'display_path'} = $display_path;
        $self->{'current_path_info'}{'req_path'} = $path;           # Crucial for shared paths

        my $okprops = $doc->createElement('D:prop');
        my $nfprops = $doc->createElement('D:prop');
        my $prop;

        dbg("-[_propfind]- : handling reqtype($reqtype) , reqinfo($reqinfo) on path(([$path])) , display_path(([$display_path]))");

        # https://datatracker.ietf.org/doc/rfc6578/
        if ( $reqtype eq 'sync-collection' ) {
            dbg("inside -[_propfind]- for sync-collection, currently unsupported");
        }

        #######################################################################################################################################
        #######################################################################################################################################
        # Most PROPFIND requests will be ultimately handled here.
        #######################################################################################################################################
        #######################################################################################################################################

        elsif ( $reqinfo eq 'prop' || $reqinfo eq 'property' ) {
            $self->{'nf_iteration'} = 0;
            for my $reqprop (@reqprops) {
                if ( ref $reqprop ne 'ARRAY' ) {
                    dbg("-[_propfind]- : ![\$reqprop was not an array, aborting due to unexpected data type.]!");
                    return;
                }
                if ( ref $reqprop->[0] eq 'HASH' ) {
                    dbg("-[_propfind]- : need to wrap child props inside parent prop");
                    foreach my $parent_prop ( @{$reqprop} ) {
                        dbg("-[_propfind]- : parent name = $parent_prop->{'parent_name'}");
                        dbg("-[_propfind]- : parent ns   = $parent_prop->{'parent_namespace'}");
                        my $name = $parent_prop->{'parent_name'};
                        my $ns   = $parent_prop->{'parent_namespace'};

                        if ( !exists $prefixes{$ns} ) {
                            dbg( "-[_propfind]- : ruhrohraggy, no $ns found in our known list:", \%prefixes );
                        }
                        dbg( "-[_propfind]- : sending off request to _process_property ($ns,$name)", $reqprop->[0] );
                        my ( $ok_or_nf, $prop_element ) = $self->_process_property( $prop, $ns, $name, $request, $response, $reqprop->[0] );
                        if ( $ok_or_nf == 1 ) {
                            $okprops->addChild($prop_element);
                        }
                        else {
                            $nfprops->addChild($prop_element);
                        }
                    }
                }
                else {
                    dbg("-[_propfind]- : didn't find parent_name, assuming this is a straight-forward property");
                    my ( $ns, $name ) = @$reqprop;
                    dbg("-[_propfind]- : calling _process_property for /[$ns]/ , -[$name]-");
                    my ( $ok_or_nf, $prop_element ) = $self->_process_property( $prop, $ns, $name, $request, $response, '' );
                    $okprops->addChild($prop_element);
                    if ( $ok_or_nf == 1 ) {
                        $okprops->addChild($prop_element);
                    }
                    else {
                        $nfprops->addChild($prop_element);
                    }
                }
            }
        }
        elsif ( $reqinfo eq 'propname' ) {
            $prop = $doc->createElement('D:creationdate');
            $okprops->addChild($prop);
            $prop = $doc->createElement('D:getcontentlength');
            $okprops->addChild($prop);
            $prop = $doc->createElement('D:getcontenttype');
            $okprops->addChild($prop);
            $prop = $doc->createElement('D:getlastmodified');
            $okprops->addChild($prop);
            $prop = $doc->createElement('D:resourcetype');
            $okprops->addChild($prop);
        }
        else {
            dbg("-[_propfind]- : Got unspecified reqinfo: $reqinfo, so building an allprop response for now");

            $prop = $doc->createElement('D:creationdate');
            $prop->appendText( $self->{'ctime'} );
            $okprops->addChild($prop);
            $prop = $doc->createElement('D:getcontentlength');
            $prop->appendText( $self->{'size'} );
            $okprops->addChild($prop);
            $prop = $doc->createElement('D:getcontenttype');

            if ( -d $path ) {
                $prop->appendText('httpd/unix-directory');
            }
            else {
                $prop->appendText('httpd/unix-file');
            }
            $okprops->addChild($prop);
            $prop = $doc->createElement('D:getlastmodified');
            $prop->appendText( $self->{'mtime'} );
            $okprops->addChild($prop);
            do {
                $prop = $doc->createElement('D:supportedlock');
                for my $n (qw(exclusive shared)) {
                    my $lock = $doc->createElement('D:lockentry');

                    my $scope = $doc->createElement('D:lockscope');
                    my $attr  = $doc->createElement( 'D:' . $n );
                    $scope->addChild($attr);
                    $lock->addChild($scope);

                    my $type = $doc->createElement('D:locktype');
                    $attr = $doc->createElement('D:write');
                    $type->addChild($attr);
                    $lock->addChild($type);

                    $prop->addChild($lock);
                }
                $okprops->addChild($prop);
            };
            $prop = $doc->createElement('D:resourcetype');
            if ( -d $path ) {
                my $col = $doc->createElement('D:collection');
                $prop->addChild($col);
            }
            $okprops->addChild($prop);
        }

        if ( $okprops->hasChildNodes ) {
            my $propstat = $doc->createElement('D:propstat');
            $propstat->addChild($okprops);
            my $stat = $doc->createElement('D:status');
            $stat->appendText('HTTP/1.1 200 OK');
            $propstat->addChild($stat);
            $resp->addChild($propstat);
        }
        else {
            dbg("-[_propfind]- : okprops does NOT have child nodes");
        }

        # Handle unsupported properties
        if ( $nfprops->hasChildNodes ) {
            dbg("-[_propfind]- : nfprops has child nodes, building 404 status reponses..");
            my $propstat = $doc->createElement('D:propstat');
            $propstat->addChild($nfprops);
            my $stat = $doc->createElement('D:status');
            $stat->appendText('HTTP/1.1 404 Not Found');
            $propstat->addChild($stat);
            $resp->addChild($propstat);
        }
        else {
            dbg("-[_propfind]- : nfprops does NOT have child nodes");
        }

        push( @xml_responses, $resp );
    }

    # 	dbg("trying to return the resp node.. ", \@xml_responses);
    return \@xml_responses;
}

# Property Tags are set based on the current request. We need to consider not only the primary request ( $self->{'request_info'}{'uri_decoded_safe'} ) but also
# any path set by hrefs embedded in xml request payloads.
#
# dir              - any actual directory
# file             - any actual file, such as vcards, attachments, cat memes
# vcard            - only vcards, like event .ics or .vcf files
# principal        - any request targetting a specific /principals/$principal_user/
# virtprincipals   - specific request to /principals/
# virtcalendars    - specific request to /calendars/
# virtaddressbooks - specific request to /addressbooks/
# allprop          - should be included in an allprop request if the request is relevant (we are currently handling this in a different place and need to revisit it)
# collection       - any collection, regardless of vcalendar, vaddressbook, vjournal, etc
# vcalendar        - limited to just calendar collections
# vaddressbook     - limited to just addressbook collections
# vjournal         - limited to just journal collections
#
# Note that tags can be negated in their usedby section, so a property that should never be returned for a principal could have !principal , The same is true for the query types,
# so !r:profind or !r:report .
# Each property handler can also return "404" if they decide there is nothing to return.
#
# sub _get_property_tags {
#     my ( $self, $prop, $ns, $name, $request, $response, $reqprop ) = @_;
#     logfunc();
#     my @property_tags;
# #     dbg("([_get_property_tags]) : All The Things:", $prop, $ns, $name, $request, $response, $reqprop );
#
#
#     foreach my $tag( keys %{$self->{'request_info'}{'tags'}} ) {
#         if( $self->{'request_info'}{'tags'}{$tag} == 1 ) {
#             push( @property_tags, $tag );
#         }
#     }
#     return \@property_tags;
# }

sub _process_report {
    my ( $self, $request, $response, $reqtype, $parsed_request_hr ) = @_;
    dbg( "=[_process_report]= : self and parsed_request_hr on /[$reqtype]/ : ", $self, $parsed_request_hr );
    my $doc    = XML::LibXML::Document->new( '1.0', 'utf-8' );
    my $ns     = $parsed_request_hr->{'reqtype_ns'};
    my $report = $doc->createElement( $prefixes{$ns} . ':' . $reqtype );

    # Some REPORT require special handling, this is a placeholder for those if needed in the future
    dbg( "=[_process_report]= : report: ", $report );

    return ( 1, $report );
}

sub _process_property {    ##no critic(Subroutines::ProhibitManyArgs)
    my ( $self, $prop, $ns, $name, $request, $response, $reqprop ) = @_;
    logfunc();

    dbg("_[_process_property]_ : ns(/[$ns]/) name(-[$name]-)");

    my $doc = XML::LibXML::Document->new( '1.0', 'utf-8' );

    if ( length $self->{'request_info'}{'principal_user'} && $self->{'request_info'}{'principal_user'} ne $self->{'auth_user'} ) {
        dbg("_[_process_property]_ : auth user and principal user for the request are not the same. checking to see if principal user ($self->{'request_info'}{'principal_user'}) shares the data requested with the auth user ($self->{'auth_user'}) for ([$self->{'current_path_info'}{'req_path'}]).");
        if ( $self->check_read_access( $self->{'current_path_info'}{'req_path'} ) ) {
            dbg("_[_process_property]_ : auth user $self->{'auth_user'} is allowed to read ([$self->{'current_path_info'}{'req_path'}])");

            # If we run in to a situation where we need to change $self->{'current_path_info'}{'req_path'} if the request is for another user's data that has shared the requested collection with the current auth_user
        }
        else {
            dbg("_[_process_property]_ : ![auth user $self->{'auth_user'} is NOT allowed to read]! ([$self->{'current_path_info'}{'req_path'}])");

            # Currently not seeing a way to get here, as the path is already removed prior to _process_property being called. But, leaving it for now in case we find it in the log
        }
    }

    # Here we check to see if the property is supported, in the current context, and process it if so.
    # The lookup table $lt is loaded globally at the top

    my $matched_tag = 0;
    if ( defined $lt->{$ns}{$name}{'cr'} and defined $lt->{$ns}{$name}{'usedby'} ) {

        # Currently, if we have tags from both current_path_info and request_info, we smash these together, favoring values from the current path info over the initial path request.
        # Ideally only the current_path_info tags should be considered, but since it doesn't know the full context of the request, using that alone will lose a lot of the tags we want.
        # The problem is sometimes we want to include tags from the primary request, but other times ignore it. We may want to revisit this once we get more usage reports, if it's causing
        # any problems.

        my %tag_hashes_to_search;
        if ( defined( $self->{'current_path_info'}{'tags'} ) ) {
            if ( defined( $self->{'request_info'}{'tags'} ) ) {
                %tag_hashes_to_search = ( %{ $self->{'current_path_info'}{'tags'} }, %{ $self->{'request_info'}{'tags'} } );
            }
            else {
                %tag_hashes_to_search = ( %{ $self->{'current_path_info'}{'tags'} } );    # We probably shouldn't have property requests made with no initial request URI, but perhaps from code calling functions directly this will happen.
            }
        }
        else {
            %tag_hashes_to_search = ( %{ $self->{'request_info'}{'tags'} } );
        }

        # See if the property expects to be handled by this particular query type, or is explicitly denied
        my $query_type = 'r:' . lc( $self->{'request_info'}{'method'} );
        dbg("_[_process_property]_ : checking for $query_type support in property proccessor for /[$ns]/ +[$name]+");

        # See if the query type was blacklisted
        if ( grep ( { $_ eq '!' . $query_type } @{ $lt->{$ns}{$name}{'usedby'} } ) ) {
            dbg("_[_process_property]_ : $ns:$name does not apply to $query_type requests");
            $matched_tag = 0;

            # Otherwise, check the property tags
        }
        elsif ( grep ( { $_ eq $query_type } @{ $lt->{$ns}{$name}{'usedby'} } ) ) {
            dbg("_[_process_property]_ : /[$ns]/ +[$name]+ does apply to $query_type requests");
            dbg( "_[_process_property]_ : did not rule out by query type, looking at tags for current property to see if matches. Have vs Wanted :", \%tag_hashes_to_search, \@{ $lt->{$ns}{$name}{'usedby'} } );
            my $is_property_banned = 0;
            foreach my $usedby ( sort @{ $lt->{$ns}{$name}{'usedby'} } ) {    # sort here is vital, as it puts the !negations at the front
                if ( $usedby =~ m/^\!(.+)/ ) {
                    my $banned_tag = $1;
                    if ( $tag_hashes_to_search{$banned_tag} ) {
                        dbg("_[_process_property]_ : /[$ns]/ +[$name]+ explicitly rejects handling of -[$banned_tag]-");
                        $matched_tag        = 0;
                        $is_property_banned = 1;
                        last;
                    }
                }
            }
            if ( $is_property_banned == 0 ) {
                $matched_tag++;
                dbg( "_[_process_property]_ : PROP IN: ", $prop );
                $prop = $doc->createElement( $prefixes{$ns} . ':' . $name );    # create the prop xml, then it is "filled out" and appended inside the coderef
                my $return = $lt->{$ns}{$name}{'cr'}->( $self, $doc, $prop, $ns, $name, $request, $response, $reqprop );
                if ( defined($return) && $return == 404 ) {
                    dbg("_[_process_property]_ : /[$ns]/ +[$name]+ handler returned 0 after processing, so putting in not-found property list");
                    $matched_tag = 0;
                }
                dbg( "_[_process_property]_ : PROP OUT: ", $prop );
            }
        }
        else {
            dbg("_[_process_property]_ : Ignoring request for  /[$ns]/ +[$name]+, it is not handled for +[$self->{'request_info'}{'method'}]+ requests");
        }
    }
    else {
        dbg("_[_process_property]_ : Unknown property : /[$ns]/ -[$name]-");
    }

    # If we don't support the property, or we don't support it for this particular request, put it in the 404s, using the "not-found" holder we generate for the unknown/unhandled namespace
    if ( !$matched_tag ) {
        dbg("_[_process_property]_ : Adding property /[$ns]/ -[$name]- to 404 Not Found list");
        my $prefix = $prefixes{$ns};

        if ( !defined $prefix ) {
            $prefix = 'i' . $self->{'nf_iteration'}++;
            $prefixes{$ns} = $prefix;
        }
        $prop = $doc->createElement("$prefix:$name");
        $prop->setAttribute( "xmlns:$prefix", $ns );
        return ( 0, $prop );
    }

    dbg( "_[_process_property]_ returning 1, \"#[" . $prop->toString() . "]#\"" );
    return ( 1, $prop );
}

# Handle All The Things \o/ in a lookup table which allows us to add some metadatalike stuff to the functions
# usedby is an array of tags we create when parsing requests, such as file,vcard or collection,vcalendar
# one complexity here is the r:tag , which is the request type. some properties are only meant for certain request types,
# such as PROPFIND or REPORT. this allows us to use the same request handler for multiple types without duplicating code.
# For now, we allow both PROPFIND and REPORT queries on all properties, until we are sure which ones we can limit.
sub _load_properties_lookup_table {    ##no critic(Subroutines::ProhibitExcessComplexity)

    my %lt;

    # https://datatracker.ietf.org/doc/html/rfc4918#section-15.1
    $lt{'DAV:'}{'creationdate'}{'usedby'} = [ 'file', 'dir', 'allprop', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'creationdate'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        dbg( "inside _load_properties_lookup_table for creationdate", \%prefixes );
        $prop->appendText( $self->{'ctime'} );
    };

    # https://datatracker.ietf.org/doc/html/rfc4918#section-15.2
    $lt{'DAV:'}{'displayname'}{'usedby'} = [ '!schedule-outbox', '!freebusy', 'collection', 'principal', 'allprop', 'virtprincipals', '!schedule-inbox', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'displayname'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);

        my $displayname;

        # If this is a principal request, we use the email address / username
        # This can frequently be hit with a property-search to get the displayname of a principal based on a list of all the principals, in
        # that case we want to just reflect the principal name, as we aren't using UIDs
        if ( $self->{'is_a_search'} ) {
            $displayname = $self->{'search_principal'};
        }
        elsif ( $self->{'request_info'}{'uri_decoded_safe'} =~ m/^\/principals\/.+/ ) {
            $displayname = $self->{'request_info'}{'principal_user'};
        }

        # Otherwise we see what the name is from metadata and reflect the request URI back as a fallback
        else {
            $displayname = $self->_get_metadata_property( $self->{'current_path_info'}{'req_path'}, 'displayname' );
            if ( !$displayname ) {
                $displayname = $self->{'request_info'}{'uri_decoded_safe'};
            }
        }

        #         my $matched;
        #         if($self->{'is_a_search'} == 1) {
        #             $matched = $self->_apply_search_filters($displayname);
        #         }
        #         if($matched) {
        $prop->appendText($displayname);

        #         }
    };

    # https://datatracker.ietf.org/doc/html/rfc4918#section-15.3
    # $lt{'DAV:'}{'getcontentlanguage'}{'usedby'} = [];
    # $lt{'DAV:'}{'getcontentlanguage'}{'cr'} = sub {
    #     my ($self, $doc, $prop) = ( @_ );
    #     # cpdavd does not return a Content-Language header, so this doesn't seem useful, but leaving in place for now
    # };

    # https://datatracker.ietf.org/doc/html/rfc4918#section-15.4
    $lt{'DAV:'}{'getcontentlength'}{'usedby'} = [ 'dir', 'file', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'getcontentlength'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        $prop->appendText( $self->{'size'} );
    };

    # https://datatracker.ietf.org/doc/html/rfc4918#section-15.5
    $lt{'DAV:'}{'getcontenttype'}{'usedby'} = [ 'dir', 'file', 'schedule-inbox', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'getcontenttype'}{'cr'}     = sub {
        my ( $self, $doc, $prop, ) = (@_);
        dbg("_[prop]_ [-[getcontenttype]-] : looking for contenttype of ([$self->{'current_path_info'}{'req_path'}])");

        if ( defined( $self->{'current_path_info'}{'tags'}{'schedule-inbox'} ) || -d $self->{'current_path_info'}{'req_path'} ) {

            #             $prop->appendText('httpd/unix-directory');
            $prop->appendText('text/calendar');
        }
        else {
            # Override for ics and vcf files, this lets the client know it's something to ask for a REPORT on
            if ( $self->_is_path_ics( $self->{'current_path_info'}{'req_path'} ) ) {
                dbg("_[prop]_ [-[getcontenttype]-] : path ([$self->{'current_path_info'}{'req_path'}]) ends in ics ?");
                $prop->appendText('text/calendar');
            }
            elsif ( $self->_is_path_vcf( $self->{'current_path_info'}{'req_path'} ) ) {
                dbg("_[prop]_ [-[getcontenttype]-] : path ([$self->{'current_path_info'}{'req_path'}]) ends in vcf ?");
                $prop->appendText('text/vcard');
            }
            else {
                $prop->appendText('httpd/unix-file');
            }
        }
    };

    # https://datatracker.ietf.org/doc/html/rfc4918#section-15.6
    $lt{'DAV:'}{'getetag'}{'usedby'} = [ 'dir', 'file', 'schedule-inbox', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'getetag'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $etag;
        if ( $self->{'current_path_info'}{'tags'}{'schedule-inbox'} ) {

            # Drop the .inbox and stat the directory. When processing partstat change requests, we "touch" this dir so this etag should be effective
            my @parts = split( '/', $self->{'current_path_info'}{'fs_root'} );
            pop @parts;
            my $stat_path = join( '/', @parts );
            dbg("_[prop]_ [-[getetag]-] : getting inbox etag from ([$stat_path])");
            $etag = $self->_get_etag($stat_path);
        }
        else {
            $etag = $self->_get_etag( $self->{'current_path_info'}{'req_path'} );
        }
        if ( length($etag) ) {
            $prop->appendText($etag);
        }
        else {
            dbg( "_[prop]_ [-[getetag]-] : Could not find etag for ([" . $self->{'current_path_info'}{'req_path'} . "])" );
            return 404;
        }
    };

    # https://datatracker.ietf.org/doc/html/rfc4918#section-15.7
    $lt{'DAV:'}{'getlastmodified'}{'usedby'} = [ 'dir', 'file', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'getlastmodified'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        $prop->appendText( $self->{'mtime'} );
    };

    # https://datatracker.ietf.org/doc/html/rfc4918#section-15.8
    # lockdiscovery - haven't seen it used yet

    # https://datatracker.ietf.org/doc/html/rfc4918#section-15.9
    # load sharing hr, if populated and uri is owned by user, "shared-owner". if populated and not owned by user, just "shared".
    # https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-sharing.txt  5.2.1

    $lt{'DAV:'}{'resourcetype'}{'usedby'} = [ 'collection', 'principal', 'schedule-inbox', 'schedule-outbox', 'freebusy', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'resourcetype'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);

        dbg("_[prop]_ [-[resourcetype]-] : path is $self->{'current_path_info'}{'req_path'}");

        # Handle based on tags set during _parse_request_path
        if ( $self->{'current_path_info'}{'tags'}{'schedule-inbox'} ) {
            my $col = $doc->createElement('D:collection');
            $prop->addChild($col);
            my $box = $doc->createElement('C:schedule-inbox');
            $prop->addChild($box);
        }
        elsif ( $self->{'current_path_info'}{'tags'}{'schedule-outbox'} ) {
            my $col = $doc->createElement('D:collection');
            $prop->addChild($col);
            my $box = $doc->createElement('C:schedule-outbox');
            $prop->addChild($box);
        }
        elsif ( $self->{'current_path_info'}{'tags'}{'freebusy'} ) {    # Not a collection, according to CCS output
            my $col = $doc->createElement('CS:free-busy-url');
            $prop->addChild($col);
        }

        # Ensure special requests to /calendar/ and /principals/ are shown as a collection, only.
        # We can't use the virt* tags as they get applied to other things as well that would otherwise fall through to the else block after this
        #
        #         if( defined $self->{'request_info'}{'tags'}{'virtcalendars'}    && $self->{'request_info'}{'tags'}{'virtcalendars'} == 1
        #          or defined $self->{'request_info'}{'tags'}{'virtprincipals'}   && $self->{'request_info'}{'tags'}{'virtprincipals'} == 1
        #          or defined $self->{'request_info'}{'tags'}{'virtaddressbooks'} && $self->{'request_info'}{'tags'}{'virtaddressbooks'} == 1 ) {
        if ( $self->{'request_info'}{'uri_decoded_safe'} =~ m/^\/(calendars|principals|addressbooks)\/{0,1}$/ ) {
            dbg("_[prop]_ [-[resourcetype]-] : request is for a special type, handling as a collection");
            my $col = $doc->createElement('D:collection');
            $prop->addChild($col);
        }
        else {
            # Ensure a (virtual) principal url request is reported as a principal collection
            if ( $self->{'request_info'}{'uri_decoded_safe'} =~ m/^\/principals\/.+$/ ) {
                dbg("_[prop]_ [-[resourcetype]-] : we've got a /principals/.+ request, so that's a collection and principal resource type.");
                my $col = $doc->createElement('D:collection');
                $prop->addChild($col);
                my $princ = $doc->createElement('D:principal');
                $prop->addChild($princ);

                # if asking for resourcetype AND current-user-privilege-set, return a resourcetype for each directory under $path
            }
            elsif ( -d $self->{'current_path_info'}{'req_path'} ) {
                my $col = $doc->createElement('D:collection');
                $prop->addChild($col);
                my $type = $self->_get_metadata_property( $self->{'current_path_info'}{'req_path'}, 'type' );
                if ( $type eq 'VCALENDAR' ) {
                    my $col2 = $doc->createElement('C:calendar');
                    $prop->addChild($col2);

                    # Add shared-owner only if sharing
                    my $sharing_hr = $self->load_sharing();
                    foreach my $sharer ( keys %{$sharing_hr} ) {
                        if ( $sharer eq $self->{'current_path_info'}{'principal_user'} ) {
                            my $shared_owner = $doc->createElement('CS:shared-owner');
                            $prop->addChild($shared_owner);
                        }
                    }
                }
                elsif ( $type eq 'VADDRESSBOOK' ) {
                    my $col2 = $doc->createElement('CR:addressbook');
                    $prop->addChild($col2);
                }
                else {
                    dbg("_[prop]_ [-[resourcetype]-] : !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! Could not determine the resource type for ([$self->{'current_path_info'}{'req_path'}])");
                }
            }
        }
    };

    # https://datatracker.ietf.org/doc/html/rfc4918#section-15.10
    # supportedlock - haven't seen it used yet

    # https://datatracker.ietf.org/doc/rfc6578/

    # Properly implementing this requires a backend method to store sync sync-tokens sent from the client along with a snapshot of data on the server, then locally recording all changes along with a new sync-token
    # and returning the new sync-token to the client in a sync-collection response.
    # If we decide to implement this, we can generate a token hash and save it to the metadata for each collection, keeping it updated as things modify stuff inside.
    #
    # $lt{'DAV:'}{'sync-token'}{'usedby'} = ['collection','file'];
    # $lt{'DAV:'}{'sync-token'}{'cr'} = sub {
    #     my ($self, $doc, $prop) = ( @_ );
    #     my $token = $self->_get_etag($path);
    #     $prop->appendText($token);
    # };

    # https://datatracker.ietf.org/doc/html/rfc3744#section-4.2
    $lt{'DAV:'}{'principal-URL'}{'usedby'} = [ 'collection', 'file', 'dir', 'principal', 'virtprincipals', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'principal-URL'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $prop_href = $doc->createElement('D:href');
        my $principal_user;
        dbg( "_[principal-URL]_ : self :", $self );
        if ( $self->{'is_a_search'} ) {
            $principal_user = $self->{'search_principal'};
        }
        else {
            $principal_user = $self->{'request_info'}{'principal_user'} || $self->{'auth_user'};
        }
        $prop_href->appendText( '/principals/' . $principal_user . '/' );
        $prop->addChild($prop_href);
    };

    # https://datatracker.ietf.org/doc/html/rfc3744#section-4.3
    $lt{'DAV:'}{'group-member-set'}{'usedby'} = [ 'collection', 'principal', 'dir', 'file', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'group-member-set'}{'cr'}     = sub {
        my ( $self, $doc, $prop, $ns, $name, $request, $response, $reqprop ) = (@_);
        my $sharing_hr = $self->load_sharing();
        dbg( "_[prop]_ [-[group-member-set]-] : sharing_hr, self :", $sharing_hr, $self, $prop, $ns, $name, $request, $response, $reqprop );

        # group-member-set is for finding out which groups a principal belongs to and can include properties to query for each group.
        # The query will be to either a collection or to virtual resource like /principals/user@dom.tld/calendar-proxy-write/ . For the latter, the intent of
        # the request is to find out which users (may) have been delegated access to the principal user@dom.tld . Each one of those gets their own <response> group.

        my $principal = $self->{'current_path_info'}{'principal_user'};

        my $proxy_config_hr = $self->load_proxy_config_data();
        foreach my $delegator ( keys %{$proxy_config_hr} ) {
            if ( $principal eq $delegator ) {
                dbg( "_[prop]_ [-[group-member-set]-] : Found principal has proxy config data :", $proxy_config_hr->{$delegator} );
                foreach my $delegatee ( keys %{ $proxy_config_hr->{$delegator} } ) {
                    dbg("_[prop]_ [-[group-member-set]-] : checking if this ($delegatee) is in the current read/write requested group");
                    if ( $proxy_config_hr->{$delegator}{$delegatee} eq $self->{'request_info'}{'tags'}{'calendar-proxy'} ) {
                        dbg("_[prop]_ [-[group-member-set]-] : yes, we need to process the props for $delegatee");

                        # Name is used for the href
                        # create <response> element
                        my $response_el = $doc->createElement('D:response');

                        # create and add href of delegating principal to <response>
                        my $href_el = $doc->createElement('D:href');
                        $href_el->appendText( '/principals/' . $delegatee . '/' );
                        $response_el->addChild($href_el);

                        # create <propstat> element
                        my $propstat_el = $doc->createElement('D:propstat');

                        # create <prop> element
                        my $subprops_el = $doc->createElement('D:prop');

                        # iterate through the requested properties / subprops, add each to <prop> element. These properties need to be processed in relation to the group, not the request.
                        if ( ref $reqprop eq 'HASH' && defined( $reqprop->{'subprops'} ) ) {
                            foreach my $subprop_ar ( @{ $reqprop->{'subprops'} } ) {
                                dbg( "_[prop]_ [-[group-member-set]-] : subprop is : ", $subprop_ar );

                                # Use the search overrides for some common properties. If we find properties queried that don't support it, add it to them.
                                $self->{'is_a_search'}      = 1;
                                $self->{'search_principal'} = $delegatee;
                                my ( $ns, $name ) = @{$subprop_ar};
                                my $subprop_el = $doc->createElement( $prefixes{$ns} . ':' . $name );
                                dbg("_[prop]_ [-[group-member-set]-] : need to process /[$ns]/ : -[$name]- as a subproperty of $reqprop->{'parent_name'}");
                                my ( $ok_or_nf, $subprop_element ) = $self->_process_property( $subprop_el, $ns, $name, $request, $response, $reqprop );
                                if ( $ok_or_nf == 1 ) {
                                    $subprops_el->addChild($subprop_element);
                                }
                            }
                        }

                        # create <status> element
                        my $status_el = $doc->createElement('D:status');
                        $status_el->appendText('HTTP/1.1 200 OK');

                        # add <status> and <prop> elements to <propstat>
                        $propstat_el->addChild($status_el);
                        $propstat_el->addChild($subprops_el);

                        # add <propstat> to <response>
                        $response_el->addChild($propstat_el);

                        # add <response> to $prop
                        $prop->addChild($response_el);
                    }
                }
            }
        }
    };

    # https://datatracker.ietf.org/doc/html/rfc3744#section-4.4
    # Currently the only groups we support are the calendar-proxy-read and calendar-proxy-write ones, but if/when more are added,
    # we will need to expand this.
    $lt{'DAV:'}{'group-membership'}{'usedby'} = [ 'collection', 'vcard', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'group-membership'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $proxy_hr = $self->load_proxy_config_data();
        dbg( "_[prop]_ [-[group-membership]-] : sharing_hr, self :", $proxy_hr, $self );

        my $collection     = $self->{'request_info'}{'collection'};
        my $realm          = $self->{'request_info'}{'realm'};
        my $principal_user = $self->{'request_info'}{'principal_user'};

        # Note the RFC does not mention the $grant , however this is the behavior of existing implementations
        if ( defined $proxy_hr->{$principal_user} ) {
            dbg("_[prop]_ [-[group-membership]-] : we have proxy info for $principal_user");
            foreach my $group_member ( keys %{ $proxy_hr->{$principal_user} } ) {
                my $grant;

                # Check for the exact string rather than just blindly setting $grant to whatever is in the .proxy_config file
                if ( $proxy_hr->{$principal_user}{$group_member} eq 'calendar-proxy-read' ) {
                    $grant = 'calendar-proxy-read';
                }
                elsif ( $proxy_hr->{$principal_user}{$group_member} eq 'calendar-proxy-write' ) {
                    $grant = 'calendar-proxy-write';
                }
                my $member_href = $doc->createElement('D:href');
                $member_href->appendText("/principals/$group_member/$grant");
                $prop->addChild($member_href);
            }
        }
        else {
            dbg( "_[prop]_ [-[group-membership]-] : we do not have proxy info for $principal_user", $self );
        }
    };

    # https://datatracker.ietf.org/doc/html/rfc3744#section-5.1
    $lt{'DAV:'}{'owner'}{'usedby'} = [ 'collection', 'principal', 'file', 'discovery', 'schedule-inbox', 'schedule-outbox', 'freebusy', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'owner'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $prop_href = $doc->createElement('D:href');

        dbg( "_[prop]_ [-[owner]-] : self : ", $self );
        if ( defined $self->{'current_path_info'}{'principal_user'} ) {
            $prop_href->appendText( '/principals/' . $self->{'current_path_info'}{'principal_user'} . '/' );
            $prop->addChild($prop_href);
        }
    };

    # https://datatracker.ietf.org/doc/html/rfc3744#section-5.2
    # group - not needed yet

    # https://datatracker.ietf.org/doc/html/rfc3744#section-5.3
    # supported-privilege-set - not needed yet, very complex

    # https://datatracker.ietf.org/doc/html/rfc3744#section-5.4
    # Original check also included if $self->_get_metadata_property( $self->{'current_path_info'}{'req_path'}, 'type' ) ne 'PRINCIPAL'
    $lt{'DAV:'}{'current-user-privilege-set'}{'usedby'} = [ 'collection', 'discovery', 'dir', 'file', 'schedule-inbox', 'schedule-outbox', 'freebusy', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'current-user-privilege-set'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);

        my %total_perms;
        my %read_perms        = ( 'D:read' => 1, 'D:read-current-user-privilege-set' => 1, 'C:read-free-busy' => 1 );
        my %write_perms       = ( 'D:all'  => 1, 'D:write'  => 1, 'D:write-properties' => 1, 'D:write-content' => 1, 'C:schedule' => 1 );
        my %proxy_write_perms = ( 'D:bind' => 1, 'D:unbind' => 1, 'D:read-acl'         => 1, 'D:write-acl'     => 1, 'D:unlock'   => 1 );

        # Account owner gets full perms
        if ( $self->{'current_path_info'}{'principal_user'} eq $self->{'auth_user'} ) {
            dbg("_[prop]_ [-[current-user-privilege-set]-] : It looks like the authed user owns ([$self->{'current_path_info'}{'req_path'}]), allowing full access");
            %total_perms = ( %total_perms, %read_perms, %write_perms, %proxy_write_perms );
        }
        else {
            # Check sharing
            dbg("_[prop]_ [-[current-user-privilege-set]-] : Check to see if authed user is allowcated any permissions to ([$self->{'current_path_info'}{'req_path'}])");
            my $uri_sharing_hr = $self->get_sharing_for_uri( $self->{'current_path_info'}{'req_path'} );
            if ( grep /r/, $uri_sharing_hr->{ $self->{'auth_user'} } ) {
                %total_perms = ( %total_perms, %read_perms );
            }
            if ( grep /w/, $uri_sharing_hr->{ $self->{'auth_user'} } ) {
                %total_perms = ( %total_perms, %write_perms );
            }

            # And check proxy config
            my $proxy_config_hr = $self->load_proxy_config_data();
            if ( length $proxy_config_hr->{ $self->{'request_info'}{'principal_user'} }{ $self->{'auth_user'} } ) {
                my $perm = $proxy_config_hr->{ $self->{'request_info'}{'principal_user'} }{ $self->{'auth_user'} };
                dbg("Found proxy config giving permission : $perm");
                if ( $perm eq 'calendar-proxy-read' ) {
                    %total_perms = ( %total_perms, %read_perms );
                }
                elsif ( $perm eq 'calendar-proxy-write' ) {
                    %total_perms = ( %total_perms, %read_perms, %write_perms, %proxy_write_perms );
                }
            }
        }
        dbg( "_[prop]_ [-[current-user-privilege-set]-] : Current path info: ", $self->{'current_path_info'} );
        if ( $self->{'current_path_info'}{'req_path'} =~ m/\.outbox$/ ) {
            $total_perms{'C:schedule'}               = 1;
            $total_perms{'C:schedule-send'}          = 1;
            $total_perms{'C:schedule-send-reply'}    = 1;
            $total_perms{'C:schedule-send-freebusy'} = 1;
        }
        elsif ( $self->{'current_path_info'}{'req_path'} =~ m/\.inbox$/ ) {
            $total_perms{'C:schedule'}                = 1;
            $total_perms{'C:schedule-deliver'}        = 1;
            $total_perms{'C:schedule-deliver-reply'}  = 1;
            $total_perms{'C:schedule-query-freebusy'} = 1;
        }
        elsif ( $self->{'current_path_info'}{'req_path'} =~ m/\.freebusy$/ ) {
            $total_perms{'C:schedule'}         = 1;
            $total_perms{'C:schedule-deliver'} = 1;
        }
        dbg( "_[prop]_ [-[current-user-privilege-set]-] : total perms for $self->{'auth_user'} on ([$self->{'current_path_info'}{'req_path'}]) is : ", \%total_perms );

        for my $priv ( keys %total_perms ) {
            my $prop_priv        = $doc->createElement('D:privilege');
            my $prop_priv_itself = $doc->createElement($priv);
            $prop_priv->addChild($prop_priv_itself);
            $prop->addChild($prop_priv);
        }
    };

    # https://datatracker.ietf.org/doc/html/rfc3744#section-5.5
    # acl - not needed yet, very complex

    # https://datatracker.ietf.org/doc/html/rfc3744#section-5.6
    # acl-restrictions - not needed yet, very complex

    # https://datatracker.ietf.org/doc/html/rfc3744#section-5.7
    # inherited-acl-set - not needed yet, inherently complex

    # https://datatracker.ietf.org/doc/html/rfc3744#section-5.8
    $lt{'DAV:'}{'principal-collection-set'}{'usedby'} = [ 'collection', 'principal', 'dir', 'file', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'principal-collection-set'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $prop_href = $doc->createElement('D:href');
        $prop_href->appendText('/principals/');
        $prop->addChild($prop_href);
    };

    # https://datatracker.ietf.org/doc/html/rfc5397#section-3
    $lt{'DAV:'}{'current-user-principal'}{'usedby'} = [ 'collection', 'dir', 'file', 'principal', 'discovery', 'r:propfind', 'r:report' ];    # anywhere and always ?
    $lt{'DAV:'}{'current-user-principal'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $prop_href = $doc->createElement('D:href');
        $prop_href->appendText( '/principals/' . $self->{'auth_user'} . '/' );
        $prop->addChild($prop_href);
    };

    # https://datatracker.ietf.org/doc/html/rfc3253#section-3.1.5
    $lt{'DAV:'}{'supported-report-set'}{'usedby'} = [ 'collection', 'virtprincipals', 'principal', 'freebusy', 'r:propfind', 'r:report' ];
    $lt{'DAV:'}{'supported-report-set'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);

        # properties that are suppported in all cases
        my @globally_supported_report_properties = ( 'D:expand-property', 'D:principal-property-search' );    # acl-principal-prop-set principal-match principal-property-search calendarserver-principal-search

        # <!ELEMENT supported-report-set (supported-report*)>
        # <!ELEMENT supported-report report>
        # <!ELEMENT report ANY>

        my @additional_supported_properties;

        # This may not be 100% accurate, so make adjustments as needed, but tread carefully. It's a finicky thing so it's easy to break other requests

        # properties that are supported only for principal path requests
        if ( $self->{'request_info'}{'realm'} eq 'principals' ) {

            #             if( $self->{'request_info'}{'method'} eq 'REPORT' ) {
            push( @additional_supported_properties, 'C:free-busy-query' );

            #             }
            # properties that are supported only for principal path requests
        }
        elsif ( $self->{'request_info'}{'realm'} eq 'calendars' ) {
            if ( $self->{'request_info'}{'method'} eq 'PROPFIND' ) {

                # push( @additional_supported_properties, 'C:calendar-query' ); # complex one, and not needed, yet
                push( @additional_supported_properties, 'C:calendar-multiget' );
                push( @additional_supported_properties, 'C:free-busy-query' );

                push( @additional_supported_properties, 'C:acl-principal-prop-set' );
                push( @additional_supported_properties, 'C:principal-match' );
                push( @additional_supported_properties, 'C:principal-property-search' );

                push( @additional_supported_properties, 'C:calendarserver-principal-search' );
                push( @additional_supported_properties, 'C:calendar-query' );

                # push( @additional_supported_properties, 'C:addressbook-query' ); # save the addybook ones for later
                # push( @additional_supported_properties, 'C:addressbook-multiget' );
            }
            elsif ( $self->{'request_info'}{'method'} eq 'REPORT' ) {
                push( @additional_supported_properties, 'C:calendar-multiget' );
                push( @additional_supported_properties, 'C:free-busy-query' );
                push( @additional_supported_properties, 'C:acl-principal-prop-set' );
                push( @additional_supported_properties, 'C:principal-match' );
                push( @additional_supported_properties, 'C:principal-property-search' );

                push( @additional_supported_properties, 'C:calendarserver-principal-search' );
                push( @additional_supported_properties, 'C:calendar-query' );
            }

            # push( @additional_supported_properties, 'D:principal-match' ); # not sure we'll be using these, but keeping them on the radar for now
            # push( @additional_supported_properties, 'CS:calendarserver-principal-search' );

            # If query is REPORT to a calendar, like /calendars/user@dom.tld/calendar , the response includes global + calendar-query calendar-multiget sync-collection
            # If query is PROPFIND to a calendar, it includes global + calendar-query calendar-multiget sync-collection + free-busy-query addressbook-query addressbook-multiget

        }

        # Add others based on request
        foreach my $supported_report_property ( @globally_supported_report_properties, @additional_supported_properties ) {
            my $supported_report_el = $doc->createElement('D:supported-report');
            my $report_el           = $doc->createElement('D:report');
            my $supported_prop      = $doc->createElement($supported_report_property);
            $report_el->addChild($supported_prop);
            $supported_report_el->addChild($report_el);
            $prop->addChild($supported_report_el);
        }

    };

    # Note: Not actually documented anywhere, but mentioned in some apple docs and simple enough to reverse engineer
    # https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-sharing.txt
    # Original check also included if $self->_get_metadata_property( $path, 'type' ) eq 'VCALENDAR'
    $lt{'http://apple.com/ns/ical/'}{'calendar-order'}{'usedby'} = [ 'vcalendar', 'r:propfind', 'r:report' ];
    $lt{'http://apple.com/ns/ical/'}{'calendar-order'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $val = $self->_get_metadata_property( $self->{'current_path_info'}{'req_path'}, 'calendar-order' );
        dbg("_[calendar-order]_ : Value before = -[$val]-");
        if ( !length $val ) {
            return 404;
        }
        dbg("_[calendar-order]_ : Value after = -[$val]-");
        $prop->appendText($val);
        dbg( "_[calendar-order]_ : prop:", $prop );
    };

    # Note: Also not actually documented anywhere, but mentioned in some apple docs and simple enough to reverse engineer
    # https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-sharing.txt
    $lt{'http://apple.com/ns/ical/'}{'calendar-color'}{'usedby'} = [ 'vcalendar', 'r:propfind', 'r:report' ];
    $lt{'http://apple.com/ns/ical/'}{'calendar-color'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $val = $self->_get_metadata_property( $self->{'current_path_info'}{'req_path'}, 'calendar-color' );
        if ( !length $val ) {
            return 404;
        }
        $prop->appendText($val);
    };

    # https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-ctag.txt
    # Note: deprecated, can use same value as sync-token, but better to use webdav sync REPORT in https://datatracker.ietf.org/doc/rfc6578/
    $lt{'http://calendarserver.org/ns/'}{'getctag'}{'usedby'} = [ 'collection', 'dir', 'file', 'r:propfind', 'r:report' ];
    $lt{'http://calendarserver.org/ns/'}{'getctag'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $etag;

        # Note that when we get a request for a virtual path like /calendars/use@r.dom/calendar/.inbox/ , we really want the parent dir /calendar/
        if ( defined $self->{'current_path_info'}{'req_path'} and -e $self->{'current_path_info'}{'req_path'} ) {
            dbg("_[getctag]_ : getting etag/ctag on $self->{'current_path_info'}{'req_path'}");
            $etag = $self->_get_etag( $self->{'current_path_info'}{'req_path'} );
        }
        elsif ( defined $self->{'request_info'}{'req_path'} and -e $self->{'request_info'}{'req_path'} ) {
            dbg("_[getctag]_ : getting etag/ctag on $self->{'request_info'}{'req_path'}");
            $etag = $self->_get_etag( $self->{'request_info'}{'req_path'} );
        }
        else {
            if ( -e $self->{'request_info'}{'fs_root'} ) {
                dbg("_[getctag]_ : getting etag/ctag on $self->{'request_info'}{'fs_root'}");
                $etag = $self->_get_etag( $self->{'request_info'}{'fs_root'} );
            }
            else {
                my $parent_dir = $self->_parentdir( $self->{'request_info'}{'fs_root'} );
                if ( -e $parent_dir ) {
                    dbg("_[getctag]_ : getting etag/ctag on $parent_dir");
                    $etag = $self->_get_etag($parent_dir);
                }
            }
        }

        if ($etag) {
            $prop->appendText($etag);
        }    # Don't add if we don't have one ???
        else {
            dbg( "_[prop]_ [-[getctag]-] : Could not get an etag for " . ( $self->{'current_path_info'}{'req_path'} // '' ) . " or " . ( $self->{'request_info'}{'req_path'} // '' ) );
        }
    };

    # Not documented anywhere I could find, reverse engineered
    $lt{'http://calendarserver.org/ns/'}{'email-address-set'}{'usedby'} = [ 'collection', 'virtprincipals', 'virtcalendars', 'virtaddressbook', 'r:propfind', 'r:report' ];
    $lt{'http://calendarserver.org/ns/'}{'email-address-set'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        dbg("_[prop]_ [-[email-address-set]-] : was triggered -----------------------------=================================---------------");

        # CCS seems to use DAV: as the namespace for email-address ? haven't seen it matter, yet.
        #         my $prop_href = $doc->createElement('CS:email-address');     # This is not actually defined anywhere, but ccs and sabre both use 'email-address'
        my $prop_href = $doc->createElement('D:email-address');                                                                                       # This is not actually defined anywhere, but ccs and sabre both use 'email-address'
        my $email     = $self->{'search_principal'} // $self->{'current_path_info'}{'principal_user'} // $self->{'request_info'}{'principal_user'};
        $prop_href->appendText($email);
        $prop->addChild($prop_href);
    };

    $lt{'http://calendarserver.org/ns/'}{'calendar-availability'}{'usedby'} = [ 'collection', 'virtprincipals', 'virtcalendars', 'virtaddressbook', 'r:propfind', 'r:report' ];
    $lt{'http://calendarserver.org/ns/'}{'calendar-availability'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        dbg("_[prop]_ [-[calendar-availability]-] : was triggered -----------------------------=================================---------------");
        my $calendar_data;
        if ( open( my $avail_fh, '<', $self->{'request_info'}{'fs_base_principal_path'} . '.availability' ) ) {
            while (<$avail_fh>) {
                $calendar_data .= $_;
            }
            my $text_node = XML::LibXML::CDATASection->new($calendar_data);
            $prop->addChild($text_node);
        }
    };

    # Different clients appear to use different namespaces for this one
    $lt{'urn:ietf:params:xml:ns:caldav'}{'calendar-availability'} = $lt{'http://calendarserver.org/ns/'}{'calendar-availability'};

    # https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-sharing.txt 5.2.2
    # ex response:
    #         <invite xmlns='http://calendarserver.org/ns/'>
    #           <user>
    #             <uid>21234401-1e2d-415a-a644-ad01af19ac16</uid>
    #             <href xmlns='DAV:'>urn:x-uid:BA6C3F2B-E527-4F5B-A46C-703AEF1CE4C4</href>
    #             <common-name>test@dom.tld</common-name>
    #             <access>
    #               <read-write/>
    #             </access>
    #             <invite-noresponse/>
    #           </user>
    #         </invite>
    $lt{'http://calendarserver.org/ns/'}{'invite'}{'usedby'} = [ 'collection', 'vcard', 'r:propfind', 'r:report' ];
    $lt{'http://calendarserver.org/ns/'}{'invite'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $sharing_hr = $self->load_sharing();
        dbg( "_[prop]_ [-[invite]-] : sharing_hr = ", $sharing_hr );

        my $collection     = $self->{'current_path_info'}{'collection'}     || $self->{'request_info'}{'collection'}     || '';
        my $principal_user = $self->{'current_path_info'}{'principal_user'} || $self->{'request_info'}{'principal_user'} || '';
        if ( defined $sharing_hr->{$principal_user} ) {
            if ( defined $sharing_hr->{$principal_user}{$collection} ) {
                dbg("_[prop]_ [-[invite]-] : we have sharing info for $collection");

                # Apparently this is completely ignored by CCS when not available, so mimicing that behavior here by only adding the invite response when there is something available
                foreach my $group_member ( keys %{ $sharing_hr->{$principal_user}{$collection} } ) {
                    my @grants;
                    if ( $sharing_hr->{$principal_user}{$collection}{$group_member} eq 'r' ) {
                        push( @grants, 'read' );
                    }
                    elsif ( $sharing_hr->{$principal_user}{$collection}{$group_member} eq 'r,w' ) {
                        push( @grants, 'read-write' );
                    }
                    else {
                        dbg("_[prop]_ [-[invite]-] : !!!!!!!!!!!!!! Unknown sharing/delegation value for $group_member | $collection : $sharing_hr->{$principal_user}{$collection}{$group_member} !!!!!!!!!!!!!!!!");
                    }

                    my $user_wrapper_obj = $doc->createElement('CS:user');    # All things in the user wrapper are defined at https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-sharing.txt 6.5
                    my $user_href_obj    = $doc->createElement('D:href');
                    $user_href_obj->appendText( '/principals/' . $group_member . '/' );
                    my $user_cn_obj = $doc->createElement('CS:common-name');
                    $user_cn_obj->appendText($group_member);
                    my $user_access_obj = $doc->createElement('CS:access');    # read or write
                    foreach my $grant (@grants) {
                        my $access_obj = $doc->createElement( 'CS:' . $grant );
                        $user_access_obj->addChild($access_obj);
                    }

                    # Also one of invite-noresponse, invite-accepted, invite-declined or invite-invalid

                    $user_wrapper_obj->addChild($user_href_obj);
                    $user_wrapper_obj->addChild($user_cn_obj);
                    $user_wrapper_obj->addChild($user_access_obj);
                    $prop->addChild($user_wrapper_obj);
                }
            }
        }
        else {
            dbg("_[prop]_ [-[invite]-] : we do not have sharing info relevant to the current path");
        }
    };

    # https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-sharing.txt 5.2.3
    # Either can-be-shared or can-be-published
    $lt{'http://calendarserver.org/ns/'}{'allowed-sharing-modes'}{'usedby'} = [ 'collection', 'vcard', 'r:propfind', 'r:report' ];
    $lt{'http://calendarserver.org/ns/'}{'allowed-sharing-modes'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);

        # Load metadata, see if current_path_info is a VCALENDAR ?
        my $sharing_modes = $doc->createElement('CS:can-be-shared');
        $prop->addChild($sharing_modes);
    };

    ##### CALDAV REQUESTS ( urn:ietf:params:xml:ns:caldav )#############################################################################

    # https://datatracker.ietf.org/doc/html/rfc4791#section-5.2.5
    # Note that this same property also exists in the carddav namespace, so there is another copy of this with those handlers.
    $lt{'urn:ietf:params:xml:ns:caldav'}{'max-resource-size'}{'usedby'} = [ 'collection', 'file', 'dir', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:caldav'}{'max-resource-size'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);

        # technically it should be the size in octects, where we are using disk sizes, but this should more than suffice. We can change it later if need be.
        my $upload_limit_bytes = $self->get_upload_limit();
        $prop->appendText($upload_limit_bytes);
    };

    # https://datatracker.ietf.org/doc/html/draft-desruisseaux-caldav-sched-04#section-5.3.1
    $lt{'urn:ietf:params:xml:ns:caldav'}{'calendar-free-busy-set'}{'usedby'} = [ 'collection', 'virtprincipals', 'schedule-inbox', 'schedule-outbox', 'freebusy', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:caldav'}{'calendar-free-busy-set'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $prop_href = $doc->createElement('D:href');

        # dbg( "_[prop]_ [-[calendar-free-busy-set]-] : self is ", $self );

        # We currently default to the primary calendar, but we might want to expand this later for other calendars the user has added.
        # This would be a good candidate for a configuration option, somwhere, if the user has a calendar they want to keep more private.
        $prop_href->appendText( '/calendars/' . $self->{'current_path_info'}{'principal_user'} . '/calendar/' );
        $prop->addChild($prop_href);
    };

    # https://www.ietf.org/archive/id/draft-daboo-valarm-extensions-03.html .. sigh
    # Days of notification before event
    $lt{'urn:ietf:params:xml:ns:caldav'}{'default-alarm-vevent-date'}{'usedby'} = [ 'collection', 'virtprincipals', 'virtcalendars', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:caldav'}{'default-alarm-vevent-date'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        $prop->appendText('1');    # Currently default to 1 day
    };

    # https://www.ietf.org/archive/id/draft-daboo-valarm-extensions-03.html .. sigh #2
    # Minutes of notification before event
    $lt{'urn:ietf:params:xml:ns:caldav'}{'default-alarm-vevent-datetime'}{'usedby'} = [ 'collection', 'virtprincipals', 'virtcalendars', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:caldav'}{'default-alarm-vevent-datetime'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        $prop->appendText('15');
    };

    # https://datatracker.ietf.org/doc/html/rfc6638#section-2.1.1
    $lt{'urn:ietf:params:xml:ns:caldav'}{'schedule-outbox-URL'}{'usedby'} = [ 'collection', 'principal', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:caldav'}{'schedule-outbox-URL'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $prop_href = $doc->createElement('D:href');

        # dbg("_[prop]_ [-[schedule-outbox-URL]-] :  self: ", $self);
        if ( length $self->{'request_info'}{'principal_user'} ) {
            $prop_href->appendText( '/calendars/' . $self->{'request_info'}{'principal_user'} . '/.outbox/' );
            $prop->addChild($prop_href);
        }    # else we let it 404
    };

    # https://datatracker.ietf.org/doc/html/rfc6638#section-2.2.1
    $lt{'urn:ietf:params:xml:ns:caldav'}{'schedule-inbox-URL'}{'usedby'} = [ 'collection', 'principal', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:caldav'}{'schedule-inbox-URL'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $prop_href = $doc->createElement('D:href');

        # dbg("_[prop]_ [-[schedule-inbox-URL]-] :  self: ", $self);
        if ( length $self->{'request_info'}{'principal_user'} ) {
            $prop_href->appendText( '/calendars/' . $self->{'request_info'}{'principal_user'} . '/.inbox/' );
            $prop->addChild($prop_href);
        }    # else we let it 404
    };

    # https://datatracker.ietf.org/doc/html/rfc6638#section-2.4.1
    $lt{'urn:ietf:params:xml:ns:caldav'}{'calendar-user-address-set'}{'usedby'} = [ 'collection', 'dir', 'file', 'virtcalendars', 'virtprincipals', 'virtaddressbook', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:caldav'}{'calendar-user-address-set'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $prop_href = $doc->createElement('D:href');

        dbg( "calendar-user-address-set self:", $self );
        my $principal_user = $self->{'username'};

        # If this is a search, we just use the searched principal
        if ( $self->{'is_a_search'} ) {
            $principal_user = $self->{'search_principal'};
        }

        # For now, we only support one email. If the path is /user/$user*, we use $user . If the path is an actual calendar or ics, we use the authenticated user.
        elsif ( length $self->{'current_path_info'}{'principal_user'} ) {
            $principal_user = $self->{'current_path_info'}{'principal_user'};
        }

        # This is mainly used to help auto complete attendees when inviting users, so if we skip the mailto:$systemuser , it shows up as "/principals/$systemuser/" in the name search,
        # which is odd.
        $prop_href->appendText( 'mailto:' . $principal_user );
        $prop->addChild($prop_href);

        my $prop_href2 = $doc->createElement('D:href');
        $prop_href2->appendText("/principals/$principal_user/");
        $prop->addChild($prop_href2);
    };

    $lt{'http://calendarserver.org/ns/'}{'record-type'}{'usedby'} = [ 'collection', 'dir', 'file', 'virtcalendars', 'virtprincipals', 'virtaddressbook', 'r:propfind', 'r:report' ];
    $lt{'http://calendarserver.org/ns/'}{'record-type'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);

        # For now we only support 'users''
        $prop->appendText('users');
    };

    # https://datatracker.ietf.org/doc/html/rfc6638#section-2.4.2
    $lt{'urn:ietf:params:xml:ns:caldav'}{'calendar-user-type'}{'usedby'} = [ 'collection', 'dir', 'file', 'virtcalendars', 'virtprincipals', 'virtaddressbook', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:caldav'}{'calendar-user-type'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);

        # Options are any CUTYPE from https://datatracker.ietf.org/doc/html/rfc5545#section-3.2.3 : GROUP , RESOURCE , ROOM , UNKNOWN , X-customstuff , "any other IANA-registered type"
        # For now we only support INDIVIDUAL, but GROUP and ROOM seem like prime candidates for future iterations
        $prop->appendText('INDIVIDUAL');
    };

    # https://datatracker.ietf.org/doc/html/rfc4791#section-9.6
    # Note - We only support a very limited use of this property for now
    $lt{'urn:ietf:params:xml:ns:caldav'}{'calendar-data'}{'usedby'} = [ 'vcard', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:caldav'}{'calendar-data'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        dbg("_[prop]_ [-[calendar-data]-] : asking get_data_from_file on ([$self->{'current_path_info'}{'req_path'}]) for data");
        my $caldata = $self->get_data_from_file( $self->{'current_path_info'}{'req_path'} );
        if ( length $caldata ) {
            my $text_node = XML::LibXML::CDATASection->new($caldata);
            $prop->addChild($text_node);
        }
        else {
            return 404;
        }
    };

    # https://datatracker.ietf.org/doc/html/rfc4791#section-5.2.1
    $lt{'urn:ietf:params:xml:ns:caldav'}{'calendar-description'}{'usedby'} = [ 'vcalendar', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:caldav'}{'calendar-description'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $desc = $self->_get_metadata_property( $self->{'current_path_info'}{'req_path'}, 'description' ) || 'N/A';
        $prop->appendText("$desc");
    };

    # https://datatracker.ietf.org/doc/html/rfc4791#section-5.2.3
    $lt{'urn:ietf:params:xml:ns:caldav'}{'supported-calendar-component-set'}{'usedby'} = [ 'collection', 'schedule-inbox', 'schedule-outbox', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:caldav'}{'supported-calendar-component-set'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);

        # Only VCALENDAR types can be included here, so:
        # VEVENT    - cal events
        # VTODO     - to-do items
        # VJOURNAL  - journal entries
        # VFREEBUSY - availability info
        # VALARM    - alarms and reminders
        # Currently we only support VEVENT, VTODO and VJOURNAL components
        if ( $self->{'current_path_info'}{'tags'}{'vaddressbook'} ) {
            return 404;
        }
        if ( $self->{'current_path_info'}{'tags'}{'schedule-outbox'} ) {
            my $comp = $doc->createElement('C:comp');
            $comp->setAttribute( 'name', 'VEVENT' );
            $prop->addChild($comp);
            my $comp_notes = $doc->createElement('C:comp');
            $comp_notes->setAttribute( 'name', 'VTODO' );
            $prop->addChild($comp_notes);
            my $comp_freebusy = $doc->createElement('C:comp');
            $comp_freebusy->setAttribute( 'name', 'VFREEBUSY' );
            $prop->addChild($comp_freebusy);
        }
        elsif ( $self->{'current_path_info'}{'tags'}{'schedule-inbox'} ) {
            my $comp = $doc->createElement('C:comp');
            $comp->setAttribute( 'name', 'VEVENT' );
            $prop->addChild($comp);
            my $comp_notes = $doc->createElement('C:comp');
            $comp_notes->setAttribute( 'name', 'VTODO' );
            $prop->addChild($comp_notes);
        }
        else {
            dbg("_[prop]_ [-[supported-calendar-component-set]-] : getting metadata property for type on path ([$self->{'current_path_info'}{'req_path'}])");
            my $resource_type = $self->_get_metadata_property( $self->{'current_path_info'}{'req_path'}, 'type' );
            if ( $resource_type eq 'VCALENDAR' ) {
                my $comp = $doc->createElement('C:comp');
                $comp->setAttribute( 'name', 'VEVENT' );
                $prop->addChild($comp);
                my $comp_notes = $doc->createElement('C:comp');
                $comp_notes->setAttribute( 'name', 'VTODO' );
                $prop->addChild($comp_notes);
                my $comp_journal = $doc->createElement('C:comp');
                $comp_journal->setAttribute( 'name', 'VJOURNAL' );
                $prop->addChild($comp_journal);
            }
        }
    };

    #     <?xml version='1.0' encoding='UTF-8'?>
    #     <multistatus xmlns='DAV:'>
    #     <response>
    #         <href>/principals/__uids__/3301A10E-4AC0-4B4C-9C95-B29752850F1B/</href>
    #         <propstat>
    #         <prop>
    #             <calendar-proxy-read-for xmlns='http://calendarserver.org/ns/'/>
    #             <calendar-proxy-write-for xmlns='http://calendarserver.org/ns/'>
    #             <response xmlns='DAV:'>
    #                 <href>/principals/__uids__/9B7A6A05-8C86-4931-8A13-74CAAF46F314/</href>
    #                 <propstat>
    #                 <prop>
    #                     <email-address-set xmlns='http://calendarserver.org/ns/'>
    #                     <email-address>test1@cptech1.test</email-address>
    #                     </email-address-set>
    #                     <calendar-user-address-set xmlns='urn:ietf:params:xml:ns:caldav'>
    #                     <href xmlns='DAV:'>mailto:test1@cptech1.test</href>
    #                     <href xmlns='DAV:'>urn:uuid:9B7A6A05-8C86-4931-8A13-74CAAF46F314</href>
    #                     <href xmlns='DAV:'>urn:x-uid:9B7A6A05-8C86-4931-8A13-74CAAF46F314</href>
    #                     </calendar-user-address-set>
    #                     <displayname>test1@cptech1.test</displayname>
    #                 </prop>
    #                 <status>HTTP/1.1 200 OK</status>
    #                 </propstat>
    #             </response>
    #             </calendar-proxy-write-for>
    #         </prop>
    #         <status>HTTP/1.1 200 OK</status>
    #         </propstat>
    #     </response>
    #     </multistatus>

    # This is very very similar to group-membership-set, but the direction of the question is reversed
    # https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-proxy.txt
    $lt{'http://calendarserver.org/ns/'}{'calendar-proxy-read-for'}{'usedby'} = [ 'collection', 'virtprincipals', 'vcard', 'r:propfind', 'r:report' ];
    $lt{'http://calendarserver.org/ns/'}{'calendar-proxy-read-for'}{'cr'}     = sub {
        my ( $self, $doc, $prop, $ns, $name, $request, $response, $reqprop ) = (@_);
        dbg("_[prop]_ [-[calendar-proxy-read-for]-] Here..");
        my $principal = $self->{'current_path_info'}{'principal_user'};

        my $proxy_config_hr = $self->load_proxy_config_data();
        foreach my $delegator ( keys %{$proxy_config_hr} ) {
            foreach my $delegatee ( keys %{ $proxy_config_hr->{$delegator} } ) {
                if ( $principal eq $delegatee ) {
                    dbg("_[prop]_ [-[calendar-proxy-read-for]-] : checking if this ($delegatee) has read-for perms for $delegator");
                    if ( $proxy_config_hr->{$delegator}{$delegatee} eq 'calendar-proxy-read' ) {
                        dbg("_[prop]_ [-[calendar-proxy-read-for]-] : yes, we need to process the props for $delegator");

                        # Name is used for the href
                        # create <response> element
                        my $response_el = $doc->createElement('D:response');

                        # create and add href of delegating principal to <response>
                        my $href_el = $doc->createElement('D:href');
                        $href_el->appendText( '/principals/' . $delegator . '/' );
                        $response_el->addChild($href_el);

                        # create <propstat> element
                        my $propstat_el = $doc->createElement('D:propstat');

                        # create <prop> element
                        my $subprops_el = $doc->createElement('D:prop');

                        # iterate through the requested properties / subprops, add each to <prop> element. These properties need to be processed in relation to the principal user, not the request.
                        if ( ref $reqprop eq 'HASH' && defined( $reqprop->{'subprops'} ) ) {
                            foreach my $subprop_ar ( @{ $reqprop->{'subprops'} } ) {
                                dbg( "_[prop]_ [-[calendar-proxy-read-for]-] : subprop is : ", $subprop_ar );

                                # Use the search overrides for some common properties. If we find properties queried that don't support it, add it to them.
                                $self->{'is_a_search'}      = 1;
                                $self->{'search_principal'} = $delegator;
                                my ( $ns, $name ) = @{$subprop_ar};
                                my $subprop_el = $doc->createElement( $prefixes{$ns} . ':' . $name );
                                dbg("_[prop]_ [-[calendar-proxy-read-for]-] : need to process /[$ns]/ : -[$name]- as a subproperty of $reqprop->{'parent_name'}");
                                my ( $ok_or_nf, $subprop_element ) = $self->_process_property( $subprop_el, $ns, $name, $request, $response, $reqprop );
                                if ( $ok_or_nf == 1 ) {
                                    $subprops_el->addChild($subprop_element);
                                }
                            }
                        }

                        # create <status> element
                        my $status_el = $doc->createElement('D:status');
                        $status_el->appendText('HTTP/1.1 200 OK');

                        # add <status> and <prop> elements to <propstat>
                        $propstat_el->addChild($status_el);
                        $propstat_el->addChild($subprops_el);

                        # add <propstat> to <response>
                        $response_el->addChild($propstat_el);

                        # add <response> to $prop
                        $prop->addChild($response_el);
                    }
                }
            }
        }
    };

    # This is very very similar to group-membership-set, but the direction of the question is reversed
    $lt{'http://calendarserver.org/ns/'}{'calendar-proxy-write-for'}{'usedby'} = [ 'collection', 'virtprincipals', 'vcard', 'r:propfind', 'r:report' ];
    $lt{'http://calendarserver.org/ns/'}{'calendar-proxy-write-for'}{'cr'}     = sub {
        my ( $self, $doc, $prop, $ns, $name, $request, $response, $reqprop ) = (@_);
        dbg("_[prop]_ [-[calendar-proxy-write-for]-] Here..");
        my $principal = $self->{'current_path_info'}{'principal_user'};

        my $proxy_config_hr = $self->load_proxy_config_data();
        foreach my $delegator ( keys %{$proxy_config_hr} ) {
            foreach my $delegatee ( keys %{ $proxy_config_hr->{$delegator} } ) {
                if ( $principal eq $delegatee ) {
                    dbg("_[prop]_ [-[calendar-proxy-write-for]-] : checking if this ($delegatee) has write-for perms for $delegator");
                    if ( $proxy_config_hr->{$delegator}{$delegatee} eq 'calendar-proxy-write' ) {
                        dbg("_[prop]_ [-[calendar-proxy-write-for]-] : yes, we need to process the props for $delegator");

                        # Name is used for the href
                        # create <response> element
                        my $response_el = $doc->createElement('D:response');

                        # create and add href of delegating principal to <response>
                        my $href_el = $doc->createElement('D:href');
                        $href_el->appendText( '/principals/' . $delegator . '/' );
                        $response_el->addChild($href_el);

                        # create <propstat> element
                        my $propstat_el = $doc->createElement('D:propstat');

                        # create <prop> element
                        my $subprops_el = $doc->createElement('D:prop');

                        # iterate through the requested properties / subprops, add each to <prop> element. These properties need to be processed in relation to the principal user, not the request.
                        if ( ref $reqprop eq 'HASH' && defined( $reqprop->{'subprops'} ) ) {
                            foreach my $subprop_ar ( @{ $reqprop->{'subprops'} } ) {
                                dbg( "_[prop]_ [-[calendar-proxy-write-for]-] : subprop is : ", $subprop_ar );

                                # Use the search overrides for some common properties. If we find properties queried that don't support it, add it to them.
                                $self->{'is_a_search'}      = 1;
                                $self->{'search_principal'} = $delegator;
                                my ( $ns, $name ) = @{$subprop_ar};
                                my $subprop_el = $doc->createElement( $prefixes{$ns} . ':' . $name );
                                dbg("_[prop]_ [-[calendar-proxy-write-for]-] : need to process /[$ns]/ : -[$name]- as a subproperty of $reqprop->{'parent_name'}");
                                my ( $ok_or_nf, $subprop_element ) = $self->_process_property( $subprop_el, $ns, $name, $request, $response, $reqprop );
                                if ( $ok_or_nf == 1 ) {
                                    $subprops_el->addChild($subprop_element);
                                }
                            }
                        }

                        # create <status> element
                        my $status_el = $doc->createElement('D:status');
                        $status_el->appendText('HTTP/1.1 200 OK');

                        # add <status> and <prop> elements to <propstat>
                        $propstat_el->addChild($status_el);
                        $propstat_el->addChild($subprops_el);

                        # add <propstat> to <response>
                        $response_el->addChild($propstat_el);

                        # add <response> to $prop
                        $prop->addChild($response_el);
                    }
                }
            }
        }
    };

    # https://datatracker.ietf.org/doc/html/rfc4791#section-6.2.1
    $lt{'urn:ietf:params:xml:ns:caldav'}{'calendar-home-set'}{'usedby'} = [ 'principal', 'discovery', 'virtprincipals', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:caldav'}{'calendar-home-set'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $prop_href = $doc->createElement('D:href');
        my $user;
        if ( length $self->{'current_path_info'}{'principal_user'} ) {
            $user = $self->{'current_path_info'}{'principal_user'};
        }
        else {
            $user = $self->{'username'};
        }
        my $url = '/calendars/' . $user . '/';
        $prop_href->appendText($url);
        $prop->addChild($prop_href);
    };

    # This determines whether or not the events in a calendar collection should be show as busy. The default is opaque, which means yes, count the events in the given collection as busy
    # https://datatracker.ietf.org/doc/html/rfc6638#section-9.1
    $lt{'urn:ietf:params:xml:ns:carddav'}{'schedule-calendar-transp'}{'usedby'} = [ 'discovery', 'collection', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:carddav'}{'schedule-calendar-transp'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $transparency = $self->_get_metadata_property( $self->{'current_path_info'}{'req_path'}, 'schedule-calendar-transp' );
        if ( $transparency ne 'transparent' ) { $transparency = 'opaque'; }
        $prop->appendText($transparency);
    };

    # https://datatracker.ietf.org/doc/html/rfc6638#section-9.2
    $lt{'urn:ietf:params:xml:ns:caldav'}{'schedule-default-calendar-URL'}{'usedby'} = [ 'principal', 'discovery', 'collection', 'schedule-inbox', 'schedule-outbox', 'virtprincipals', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:caldav'}{'schedule-default-calendar-URL'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $prop_href = $doc->createElement('D:href');
        my $user      = $self->{'current_path_info'}{'principal_user'} || $self->{'request_info'}{'principal_user'};
        my $url       = '/calendars/' . $user . '/calendar/';
        $prop_href->appendText($url);
        $prop->addChild($prop_href);
    };

    ##### CARDDAV REQUESTS ( urn:ietf:params:xml:ns:carddav )###########################################################################

    # https://datatracker.ietf.org/doc/html/rfc6352/#section-6.2.1
    $lt{'urn:ietf:params:xml:ns:carddav'}{'addressbook-description'}{'usedby'} = [ 'vaddressbook', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:carddav'}{'addressbook-description'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $desc = $self->_get_metadata_property( $self->{'current_path_info'}{'req_path'}, 'description' );
        if ( !length $desc ) {
            return 404;
        }
        $prop->appendText("$desc");
    };

    # https://datatracker.ietf.org/doc/html/rfc6352/#section-6.2.2
    $lt{'urn:ietf:params:xml:ns:carddav'}{'supported-address-data'}{'usedby'} = [ '!allprop', 'vaddressbook', 'vcard', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:carddav'}{'supported-address-data'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);

        #         $prop->appendText("vcard30; utf-8");
        my $adt = $doc->createElement('CR:address-data-type');
        $adt->setAttribute( 'content-type', 'text/vcard' );
        $adt->setAttribute( 'version',      '3.0' );
        $prop->addChild($adt);
    };

    # https://datatracker.ietf.org/doc/html/rfc6352#section-6.2.3
    # There is a calddav version of this property as well.
    $lt{'urn:ietf:params:xml:ns:carddav'}{'max-resource-size'}{'usedby'} = [ 'collection', 'file', 'dir', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:carddav'}{'max-resource-size'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);

        # technically it should be the size in octects, where we are using disk sizes, but this should more than suffice. We can change it later if need be.
        my $upload_limit_bytes = $self->get_upload_limit();
        $prop->appendText($upload_limit_bytes);
    };

    # https://datatracker.ietf.org/doc/html/rfc6352/#section-7.1.1
    $lt{'urn:ietf:params:xml:ns:carddav'}{'addressbook-home-set'}{'usedby'} = [ 'vaddressbook', 'collection', 'vcard', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:carddav'}{'addressbook-home-set'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        my $prop_href = $doc->createElement('D:href');
        my $user      = $self->{'username'};
        $prop_href->appendText("/addressbooks/$user/");
        $prop->addChild($prop_href);
    };

    # https://datatracker.ietf.org/doc/html/rfc6352/#section-10.4
    # and
    # https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-proxy.txt
    $lt{'urn:ietf:params:xml:ns:carddav'}{'address-data'}{'usedby'} = [ 'vaddressbook', 'vcard', 'r:propfind', 'r:report' ];
    $lt{'urn:ietf:params:xml:ns:carddav'}{'address-data'}{'cr'}     = sub {
        my ( $self, $doc, $prop ) = (@_);
        $prop->setAttribute( 'content-type', 'text/vcard' );
        my $data = '';
        if ( $self->_is_path_vcf( $self->{'current_path_info'}{'req_path'} ) ) {
            dbg("_[prop]_ [-[address-data]-] : asking get_data_from_file on $self->{'current_path_info'}{'req_path'} for data");
            $data = $self->get_data_from_file( $self->{'current_path_info'}{'req_path'} );
        }
        $prop->appendText($data);
    };

    return \%lt;
}

sub load_proxy_config_data {
    my ($self) = @_;
    logfunc();
    dbg( "=[load_proxy_config_data]= : load_metadata on ([" . $self->{'acct_homedir'} . '/.caldav/.proxy_config])' );
    my $raw_proxy_hr = $self->{'metadata'}->load( $self->{'acct_homedir'} . '/.caldav/.proxy_config' );
    dbg( "=[load_proxy_config_data]= : returning : ", $raw_proxy_hr );
    return $raw_proxy_hr;
}

sub save_proxy_config_data {
    my ( $self, $data_hr ) = @_;
    logfunc();

    dbg( "=[save_proxy_config_data]= : data_hr: ", $data_hr );

    # Convert the nested hash back to our .ini format
    # If delegator has no shares, remove it to avoid cruft
    my %proxy_data_hash;
    foreach my $user ( keys %{$data_hr} ) {
        dbg( "=[save_proxy_config_data]= : user is $user and now we look at ", $data_hr->{$user} );
        my $delegated_cnt = keys %{ $data_hr->{$user} };
        if ($delegated_cnt) {
            $proxy_data_hash{$user} = $data_hr->{$user};
        }
        else {
            delete $data_hr->{$user};
        }
    }
    dbg( "=[save_proxy_config_data]= : sending the following to save_metadata : ", \%proxy_data_hash );
    $self->{'metadata'}->save( \%proxy_data_hash, $self->{'acct_homedir'} . '/.caldav/.proxy_config' );
    return;
}

sub modify_proxy_config_data {
    my ( $self, $data_hr ) = @_;
    logfunc();

    # Load existing data
    my $existing_proxy_config_data_hr = $self->load_proxy_config_data();

    # Merge new data in
    dbg( "=[modify_proxy_config_data]= : new proxy config data : ", $data_hr );
    dbg( "=[modify_proxy_config_data]= : existing proxy config : ", $existing_proxy_config_data_hr );
    foreach my $delegator ( keys %{$data_hr} ) {
        foreach my $delegatee ( keys %{ $data_hr->{$delegator} } ) {
            $existing_proxy_config_data_hr->{$delegator}{$delegatee} = $data_hr->{$delegator}{$delegatee};
        }
    }
    dbg( "=[modify_proxy_config_data]= : updated proxy config data : ", $existing_proxy_config_data_hr );

    # Save updated data
    $self->save_proxy_config_data($existing_proxy_config_data_hr);
    return;
}

sub get_data_from_file {
    my ( $self, $path ) = @_;
    logfunc();

    dbg("get_data_from_file : looking in ([$path]) for calendar/card data");

    if ( !$self->check_read_access($path) ) {
        dbg("get_data_from_file : \xe2\x9d\x8c Returning undef for ([$path]) since check_read_access disallowed access");
        return undef;
    }
    if ( !-f $path ) {    # will match both files and symlinks
        dbg("get_data_from_file : \xe2\x9d\x8c ([$path]) is not a file");
        return undef;
    }
    my $data = '';
    if ( open( my $fh, '<', $path ) ) {
        while (<$fh>) {
            $data .= $_;
        }
        close($fh);
    }
    dbg("get_data_from_file : returning contents of ([$path])");
    return $data;
}

sub _get_etag {
    my ( $self, $path ) = @_;
    logfunc();
    dbg("=[_get_etag]=  : getting etag for ([$path])");
    if ( defined( $self->{'path_cache'}{$path}{'etag'} ) ) {
        dbg("=[_get_etag]=  : returning cache hit on etag for ([$path]), $self->{'path_cache'}{$path}{'etag'}");
        return $self->{'path_cache'}{$path}{'etag'};
    }
    my @stats = stat($path);
    my $etag  = $stats[9];
    if ($etag) {
        dbg("=[_get_etag]= : returning $etag");
    }
    else {
        dbg("=[_get_etag]= : could not stat etag, returning undef");
        return undef;
    }
    $self->{'path_cache'}{$path}{'etag'} = $etag;
    return $etag;
}

sub _safepath {
    my ( $self, $path ) = @_;
    logfunc();

    # first, make sure the path is absolute
    if ( $path !~ /^\// ) {
        $path = "/" . $path;
    }

    # now remove multiple slashes
    $path =~ s/\/\/+/\//g;

    # start removing '..'
    while ( $path =~ /\/\.\.\// ) {
        if ( $path =~ /^\/..(\/.+)/ ) {    # these are especially dangerous...
            $path = $1;
        }
        $path =~ s/\/[^\/]+\/\.\.\//\//;
    }

    return $path;
}

sub _is_path_vcf {
    my ( $self, $path ) = @_;
    logfunc();

    if ( ( substr $path, -4 ) eq '.vcf' ) {
        dbg("_is_path_vcf: ($path) returning 1");
        return 1;
    }
    else {
        dbg("_is_path_vcf: ($path) returning 0");
        return 0;
    }
}

sub _is_path_ics {
    my ( $self, $path ) = @_;
    logfunc();
    if ( ( substr $path, -4 ) eq '.ics' ) {
        return 1;
    }
    else {
        return 0;
    }
}

# $type is optional
sub get_collections_for_user {
    my ( $self, $user, $type ) = @_;
    logfunc();
    dbg( "get_collections_for_user : ", $self, $user );
    my $metadata_path = $self->{'acct_homedir'} . '/.caldav/' . $user . '/.metadata';
    dbg("get_collections_for_user: metadata path is $metadata_path");

    #     dbg("get_collections_for_user: checking to see if $metadata_path exists..");
    #     die "Can't get metadata from $metadata_path for $user!" if !-s $metadata_path;
    # We return an empty hash ref in this case, it should not be fatal.

    my %col_hash;
    my $metadata_hr = $self->{'metadata'}->load($metadata_path);
    dbg( "get_collections_for_user: metadata is ", $metadata_hr );
    foreach my $collection ( keys %{$metadata_hr} ) {
        my $collection_name = $collection;
        $collection_name =~ s/^\/|\/$//g;
        next if !$collection_name;                                       # Skips the "/" metadata
        next if $type && $metadata_hr->{$collection}{'type'} ne $type;
        $col_hash{$collection_name} = $metadata_hr->{$collection};
    }
    return \%col_hash;
}

sub _mail_dir_exists {
    my ( $self, $ldom, $luser ) = @_;
    dbg( "-[_mail_dir_exists]- : checking " . $self->{'acct_homedir'} . '/mail/' . $ldom . '/' . $luser );
    return -e $self->{'acct_homedir'} . '/mail/' . $ldom . '/' . $luser;
}

sub _drop_privs_if_needed {
    my ($user) = @_;
    if ( $> == 0 && $user ne 'root' ) {
        require Cpanel::AccessIds::ReducedPrivileges;
        return Cpanel::AccessIds::ReducedPrivileges->new($user);
    }
    return;
}

sub is_over_quota {
    my ($user) = @_;
    logfunc();
    dbg("is_over_quota: user=$user");

    my $sys_acct = $user;
    if ( $user =~ m/(.+)\@(.+)/ ) {
        my $luser  = $1;
        my $domain = $2;
        $sys_acct = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain) // '';
        dbg("is_over_quota: got system user “$sys_acct” from “$user”");
        die "Unable to determine owner of domain $domain\n" if !length($sys_acct);
    }

    my $homedir = Cpanel::PwCache::gethomedir($sys_acct);
    die "Unable to determine homedir for user $sys_acct\n" if !$homedir;

    my $privs_obj = _drop_privs_if_needed($sys_acct);

    # cheap quota test
    if ( open( my $quota_test_fh, '>', "$homedir/.cpdavd_quota_test" ) ) {
        if ( print $quota_test_fh "This file was created to test if an account is over their quota limit. If you see this file, something went wrong before it could be deleted, and can be deleted safely.\n" ) {
            close($quota_test_fh);
            unlink "$homedir/.cpdavd_quota_test";
            return 0;
        }
    }
    return 1;
}

# for mocking in tests.
sub _rename ( $src, $dest ) { return rename( $src, $dest ) }

# 2 reasons:
#  - When we get an uninitialized value warning while concatenating a hash element, Perl is not helpful at all about which one caused it.
#  - If something like this happens in a real request, it's likely to produce unwanted or unknown behavior.
sub _strict_concat {
    my @elements = @_;

    my $any_undef;
    my $result = join '', map {
        defined($_) ? $_ : do { ++$any_undef; '<UNDEF>' }
    } @elements;

    if ($any_undef) {
        dbg("_[_strict_concat]_ : ![bad concatenation: $result]!");
        require Carp;
        Carp::confess("bad concatenation: $result");
    }
    return $result;
}

1;
