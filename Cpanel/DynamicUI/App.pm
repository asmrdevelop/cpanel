package Cpanel::DynamicUI::App;

# cpanel - Cpanel/DynamicUI/App.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles             ();
use Cpanel::Branding::Lite::Package ();
use Cpanel::DynamicUI::Loader       ();
use Cpanel::Debug                   ();
use Cpanel::AdminBin::Serializer    ();
use Cpanel::ArrayFunc::Uniq         ();
use Cpanel::CachedCommand::Utils    ();
use Cpanel::GlobalCache             ();
use Cpanel::PwCache                 ();
use Cpanel::Locale                  ();
use Cpanel::Team::Config            ();
use Try::Tiny;

my $locale;
my ($dynamic_ui_conf_cache);

# Are we running the optimized version ?
# If we are using Branding 2.1 or later we have to be.
our $VERSION                      = 5.4;                              # Must not end in .0 or the cache may break
our $AVAILABLE_APPLICATIONS_CACHE = 'AVAILABLE_APPLICATIONS_CACHE';
our $DYNAMICUI_TOUCHFILE_DIR      = '/var/cpanel/dynamicui';

=head1 NAME

Cpanel::DynamicUI::App

=head1 DESCRIPTION

Various method that load and manipulate the application data stored
in the dynamic ui conf files.

=head1 FUNCTIONS

=head2 C<< load_dynamic_ui_conf(theme => ..., user => ..., homedir => ..., ownerhomedir => ..., ...) >>

=head3 Arguments

=over

=item Required

=over

=item 'theme': string - The name of the cPanel theme

=item 'user': string - The name of the cPanel user (system user)

=item 'homedir': string - The home directory for the cPanel user (this is used to avoid a getpwnam call)

=item 'ownerhomedir': string - The home directory for the cPanel user's owner (this is used to avoid a getpwnam call)

=back

=back

=over

=item Optional

=over

=item 'need_description': boolean - If true, the description field will be included in the 'conf' output

=item 'showdeleted': boolean - If true, items which have been removed by cascaing loads of secondary dynamicui.conf will not be removed from the 'conf' output

=item 'need_origin': boolen - If true, the origin field will be included in the 'conf' output

=item 'nocache': boolean - If true, the cache will not be updated

=item 'dui_conf_files': opaque - cached result from get_dynamicui_conf_and_cache_files

=item 'dui_cache_file': opaque - cached result from get_dynamicui_conf_and_cache_files

=item 'mtime_dui_cache_must_beat_to_be_valid': opaque - cached result from get_dynamicui_conf_and_cache_files

=back

=back

=head3 Returns

=over

=item A hashref or hash that has the following structure depending on the value of wantarray.

=over

=item 'conf': hashref - A combined dynamicui conf structure

=item 'dyalist': arrayref - A list of each dynamicui.conf along with its description

=item 'cachetime': integer - The time to use for caching (the time that this data was gathered)

=item 'version': string - The version of this module

=back

=back

=head3 Exceptions

generic exception.

=cut

sub load_dynamic_ui_conf {
    my %OPTS = @_;

    if ( $OPTS{'showdeleted'} || $OPTS{'nocache'} || !$dynamic_ui_conf_cache ) {
        _ensure_options_for_dynamic_ui_loader( \%OPTS );
        $dynamic_ui_conf_cache = Cpanel::DynamicUI::Loader::load_all_dynamicui_confs(%OPTS)->{'conf'};
    }

    return wantarray ? %{$dynamic_ui_conf_cache} : $dynamic_ui_conf_cache;
}

=head2 C<< get_available_applications(nvargslist => ..., argslist => ...) >>

Loads the dynamicui configuration for the current user and
returns applications that are enabled based on the users
feature list and the active server configuration.

=head3 Arguments

=over

=item hash

with the following possible properties:

=over

=item C<nvargslist>|C<arglist> - String

The order to sort the groups in a pipe, '|', separated list

=back

=back

=head4 Example

'pref|software|domains....'

=head3 Returns

A hashref in the format:

   'implements' => {
                     'Email_BoxTrapper' => 'boxtrapper',
                     'Database_phpMyAdmin' => 'php_my_admin',
                     'Email_Archive' => 'archive',
       ...
    },
   'grouporder' => ['files','databases'....'],
   'groups' => [
                 {
                   'group' => 'files',
                   'desc' => 'Files',
                   'items' => [
                                {
                                  'width' => '48',
                                  'itemorder' => '1',
                                  'file' => 'file_manager',
                                  'itemdesc' => 'File Manager',
                                  'feature' => 'filemanager',
              ...
              },
              ...
            ],
     },
     ...
     ],
    'index' => {
                'change_language' => [
                                       8,
                                       1
                                     ],
                'addon_domains' => [
                                     2,
                                     0
                                   ],
     ...
     }

=cut

sub get_available_applications {
    my %OPTS                  = @_;
    my $datastore_file        = Cpanel::CachedCommand::Utils::get_datastore_filename( _get_cache_file_name() );
    my $requested_group_order = $OPTS{'nvarglist'} || $OPTS{'arglist'};
    my $cache                 = _load_parsed_dynamicui_app_cache_if_valid( $datastore_file, %OPTS );
    if ($cache) {
        _augment_dynamicui_app_cache_with_index_order_and_security_tokens( $cache, $requested_group_order );
        return $cache if $cache;
    }

    # No cache
    require Cpanel::Parser::FeatureIf;
    require Cpanel::StatCache;
    Cpanel::Parser::FeatureIf::resetfeature_and_if();
    my (
        %GRPS,              # An multi-level index of 'group' and 'file' that points the the dynamicui.conf entry for the 'file'
        %GROUPDESC,         # An index of group descriptions with the keys being the 'group'
        %ITEMORDER,         # an index keys on 'file' with the value as the 'itemorder' for each item (used for sorting)
        %IMPLEMENTS,        # an of what each item 'implements' as defined by get_users_links
        %NEED_SEC_TOKEN,    # items that need the security token prepended to the application URL
        %DEFAULT_GROUP_ORDER,
        %GROUP_META,        # The full metadata for each of the dynamic application groups
        @GROUPS
    );

    my $dbrandconf = load_dynamic_ui_conf(%OPTS);

    my %parse_opts = (
        dbrandconf              => $dbrandconf,
        default_group_order_ref => \%DEFAULT_GROUP_ORDER,
        group_descriptions_ref  => \%GROUPDESC,
        items_by_group_ref      => \%GRPS,
        item_order_ref          => \%ITEMORDER,
        group_meta_ref          => \%GROUP_META
    );

    _parse_dynamic_ui_conf_into_groups_and_items(%parse_opts);

    my ( $cur_dconf, $module, $if, $feature, $url, $touch, $implements );
    my $group_num = 0;

    foreach my $group ( keys %GRPS ) {

        if (   ( length $GROUP_META{$group}{'if'} && !Cpanel::Parser::FeatureIf::ifresult( $GROUP_META{$group}{'if'} ) )
            || ( length $GROUP_META{$group}{'feature'} && !Cpanel::Parser::FeatureIf::featureresult( $GROUP_META{$group}{'feature'} ) ) ) {
            next;
        }

        my @ITEMS;
        foreach my $item (
            sort { $ITEMORDER{$a} <=> $ITEMORDER{$b} || $a cmp $b }
            keys %{ $GRPS{$group} }
        ) {
            $cur_dconf = $GRPS{$group}{$item};
            ( $module, $if, $feature, $url, $implements, $touch ) = @{$cur_dconf}{qw(module if feature url implements touch)};
            if (
                defined $module    # A touch file (not a module) in /usr/local/cpanel/Cpanel/ will determine if this icon will show up.
                && !( Cpanel::StatCache::cachedmtime( "/usr/local/cpanel/Cpanel/$module.pm", Cpanel::StatCache::cachedmtime('/usr/local/cpanel/Cpanel') ) )
            ) {
                next;
            }
            elsif (( length $if && !Cpanel::Parser::FeatureIf::ifresult($if) )
                || ( length $feature && !Cpanel::Parser::FeatureIf::featureresult($feature) ) ) {
                next;
            }
            elsif (
                defined $touch     # touch file in /var/cpanel/dynamicui drives if this icon will show up.
                && !( Cpanel::StatCache::cachedmtime( "$DYNAMICUI_TOUCHFILE_DIR/$touch", Cpanel::StatCache::cachedmtime($DYNAMICUI_TOUCHFILE_DIR) ) )
            ) {
                next;
            }
            elsif ( length $url && substr( $url, 0, 1 ) eq '/' ) {
                $NEED_SEC_TOKEN{$item} = 1;
            }
            push @ITEMS, $cur_dconf;
            $IMPLEMENTS{$implements} = $item if $implements;
        }

        if (@ITEMS) {
            push(
                @GROUPS,
                {
                    'desc'  => $GROUPDESC{$group},
                    'group' => $group,
                    'items' => \@ITEMS,
                }
            );
            $group_num++;
        }
    }
    Cpanel::Parser::FeatureIf::resetfeature_and_if();

    my $ret = {
        'needs_security_token' => \%NEED_SEC_TOKEN,         #
        'default_group_order'  => \%DEFAULT_GROUP_ORDER,    #
        'groups'               => \@GROUPS,                 #
        'implements'           => \%IMPLEMENTS,             #
        'VERSION'              => $VERSION                  #
    };

    _write_parsed_dynamicui_app_cache( $datastore_file, $ret );

    _augment_dynamicui_app_cache_with_index_order_and_security_tokens( $ret, $requested_group_order );

    return $ret;
}

=head2 C<clear_available_applications_cache>

Clears the underlying cache.

=head3 Arguments

none

=cut

sub clear_available_applications_cache {
    return Cpanel::CachedCommand::Utils::destroy( 'name' => _get_cache_file_name() );
}

sub _augment_dynamicui_app_cache_with_index_order_and_security_tokens {
    my ( $ret, $requested_group_order ) = @_;

    my $i         = 0;
    my %group_map = map { $_->{'group'} => $i++ } @{ $ret->{'groups'} };

    # Order groups.
    $ret->{'grouporder'} = scalar _get_app_list_order( $requested_group_order, $ret->{'default_group_order'} );

    # Reorder groups to match the requested order
    @{ $ret->{'groups'} } = map { $ret->{'groups'}->[ $group_map{$_} ] } grep { length $group_map{$_} } @{ $ret->{'grouporder'} };

    # Index groups
    my %INDEX;
    for my $groupnum ( 0 .. $#{ $ret->{'groups'} } ) {
        my $group_ref = $ret->{'groups'}->[$groupnum]->{'items'};
        for my $itemnum ( 0 .. $#{$group_ref} ) {
            $INDEX{ $group_ref->[$itemnum]->{'file'} } = [ $groupnum, $itemnum ];
        }
    }

    $ret->{'index'} = \%INDEX;

    # Add security token to absolute urls
    my $security_token = $ENV{'cp_security_token'} || '';
    foreach my $item ( keys %{ $ret->{'needs_security_token'} } ) {
        if ( defined $INDEX{$item} ) {
            my ( $groupnum, $itemnum ) = @{ $INDEX{$item} };
            substr( $ret->{'groups'}->[$groupnum]->{'items'}->[$itemnum]->{'url'}, 0, 0, $security_token );
        }
    }
    return 1;
}

sub _get_backup_config_mtime {

    # assume the config has never been saved so use the mtime of the directory
    # which will be updated when the file gets added or unlinked
    return ( stat($Cpanel::ConfigFiles::backup_config_touchfile) )[9] // ( stat($Cpanel::ConfigFiles::backup_config_touchfile_dir) )[9] // 0;
}

sub _load_parsed_dynamicui_app_cache_if_valid {
    my ( $datastore_file, %OPTS ) = @_;

    if ( open( my $fh, '<', $datastore_file ) ) {
        my $datastore_file_mtime = ( stat($fh) )[9];
        my $backup_config_mtime  = _get_backup_config_mtime();
        _ensure_options_for_dynamic_ui_loader( \%OPTS );
        my $dui_conf_cache_mtime = Cpanel::DynamicUI::Loader::get_dynamicui_conf_and_cache_files(%OPTS);
        my $team_file_mtime      = Cpanel::Team::Config::get_mtime_team_config( $ENV{'TEAM_USER'}, $ENV{'TEAM_OWNER'} );
        if (
            # Feature cache mtime  $Cpanel::FEATURE_CACHE_MTIME
            $Cpanel::FEATURE_CACHE_MTIME < $datastore_file_mtime &&

            # cpuser file mtime AKA $Cpanel::CPDATA{'MTIME'}
            # is already checked as part 'mtime_dui_cache_must_beat_to_be_valid'
            # so there is no reason to check it here
            # $Cpanel::CPDATA{'MTIME'} < $datastore_file_mtime &&

            # cpanel.config mtime  $Cpanel::ConfigFiles::cpanel_config_file
            ( stat($Cpanel::ConfigFiles::cpanel_config_file) )[9] < $datastore_file_mtime &&

            # global cache mtime
            Cpanel::GlobalCache::get_cache_mtime('cpanel') < $datastore_file_mtime &&

            # dynamicui mtime
            $dui_conf_cache_mtime->{'mtime_dui_cache_must_beat_to_be_valid'} < $datastore_file_mtime &&

            # backup configuration mtime
            $backup_config_mtime < $datastore_file_mtime &&

            # team configuration mtime
            $team_file_mtime < $datastore_file_mtime
        ) {
            local $@;
            my $ret;
            eval { $ret = Cpanel::AdminBin::Serializer::LoadFile($fh); };
            if ( $ret && ref $ret && $ret->{'VERSION'} eq $VERSION ) {
                return $ret;
            }
        }

        # Load dui_conf_files, dui_cache_file, mtime_dui_cache_must_beat_to_be_valid
        # into %OPTS so that the load_dynamic_ui_conf  call can use them
        @OPTS{ keys %$dui_conf_cache_mtime } = values %$dui_conf_cache_mtime;
    }
    return;
}

sub _write_parsed_dynamicui_app_cache {
    my ( $datastore_file, $ret ) = @_;

    require Cpanel::FileUtils::Write;
    my $write_ok = 0;
    try {
        $write_ok = Cpanel::FileUtils::Write::overwrite(
            $datastore_file,
            Cpanel::AdminBin::Serializer::Dump($ret),
            0600
        );
    }
    catch {
        Cpanel::Debug::log_warn("Failed to save cache to $datastore_file: $_");
    };
    return $write_ok;
}

sub _parse_dynamic_ui_conf_into_groups_and_items {
    my (%OPTS) = @_;

    my (
        $dbrandconf,
        $default_group_order_ref,
        $group_descriptions_ref,
        $items_by_group_ref,
        $item_order_ref,
        $group_meta_ref
      )
      = @OPTS{
        qw(
          dbrandconf
          default_group_order_ref
          group_descriptions_ref
          items_by_group_ref
          item_order_ref
          group_meta_ref
        )
      };

    foreach my $item ( keys %{$dbrandconf} ) {
        my $cur_dconf = $dbrandconf->{$item};
        my ( $group, $groupdesc, $file, $itemorder, $grouporder ) = @{$cur_dconf}{qw(group groupdesc file itemorder grouporder)};
        if ( length $group && ( !defined $file || defined $grouporder ) ) {
            $group_descriptions_ref->{$group}  = $groupdesc                                                                                                                       if defined $group_descriptions_ref;
            $group_meta_ref->{$group}          = $cur_dconf                                                                                                                       if defined $group_meta_ref;
            $default_group_order_ref->{$group} = int( ( length $grouporder && index( $grouporder, '$' ) == 0 ? _get_dynamic_group_order($grouporder) : $grouporder ) || 1000000 ) if defined $default_group_order_ref;
        }
        elsif ( defined $group && length $file ) {
            $items_by_group_ref->{$group}{$file} = $cur_dconf            if defined $items_by_group_ref;
            $item_order_ref->{$file}             = $itemorder || 1000000 if defined $item_order_ref;
        }
    }
    return 1;
}

# lookup custom position file
#  if sub is called with invalid input, or value (from a dynamicui value) is
#  invalid, consider it "out of bounds" and return a default value that will
#  place it at the end of the groupings
sub _get_dynamic_group_order {
    my ($item) = @_;
    my $order = 100000;
    if ( !$item || $item !~ m/\$DYNAMIC_ORDERING\{\'?([^\'\}]+)\'?\}/ ) {
        return $order;
    }
    my $group = $1;
    require Cpanel::Path::Safety;
    my $file = Cpanel::Path::Safety::make_safe_for_path( _grouporder_override_dir() . '/' . $group );
    require Cpanel::LoadFile;
    $order = Cpanel::LoadFile::loadfile($file);
    chomp($order) if length $order;
    return $order || 100000;
}

sub _grouporder_override_dir {
    return '/var/cpanel/dynamicui_grouporder';
}

sub _ensure_options_for_dynamic_ui_loader {
    my ($opts_ref) = @_;
    $opts_ref->{'user'} ||= $Cpanel::user || Cpanel::PwCache::getusername();

    #When called as root, we'll get $opts_ref->{'theme'};
    #when called as the user we'll get %Cpanel::CPDATA.
    $opts_ref->{'theme'}        ||= $Cpanel::CPDATA{'RS'};
    $opts_ref->{'homedir'}      ||= ( $> == 0 ? Cpanel::PwCache::gethomedir($>) : ( $Cpanel::homedir || Cpanel::PwCache::gethomedir($>) ) );
    $opts_ref->{'ownerhomedir'} ||= Cpanel::Branding::Lite::Package::_getbrandingdir();
    $opts_ref->{'brandingpkg'}  ||= Cpanel::Branding::Lite::Package::_getbrandingpkg();

    if ( !$opts_ref->{'theme'} ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("I need a theme!");
    }
    return 1;
}

# Used only for api1 Cpanel::Branding::Branding_getapplistorder
sub _get_default_app_list_order {
    my (%OPTS) = @_;
    my $dbrandconf = load_dynamic_ui_conf(%OPTS);

    my $default_group_order_ref = {};

    my %parse_opts = (
        dbrandconf              => $dbrandconf,
        default_group_order_ref => $default_group_order_ref
    );

    _parse_dynamic_ui_conf_into_groups_and_items(%parse_opts);
    return $default_group_order_ref;
}

# Note: Cpanel::Branding calls this for legacy support
# Please do not call it externally in new code
sub _get_app_list_order {
    my ( $given_order, $default_group_order_ref ) = @_;

    $default_group_order_ref ||= _get_default_app_list_order();

    if ($given_order) {
        $given_order = [ split m{[|]}, $given_order ] if !ref $given_order;

        # Note: since given_order comes from an untrusted source
        # we only accept items that are in the default_group_order_ref
        @$given_order = grep { $default_group_order_ref->{$_} } @$given_order;
    }

    my @ordered = Cpanel::ArrayFunc::Uniq::uniq(
        $given_order ? @$given_order : (),
        ( sort { $default_group_order_ref->{$a} <=> $default_group_order_ref->{$b} } sort keys %$default_group_order_ref ),
    );

    return wantarray ? @ordered : \@ordered;
}

sub _locale {
    return ( $locale ||= Cpanel::Locale::lh() );
}

sub _get_cache_file_name {
    my $theme    = $Cpanel::CPDATA{'RS'}     || '';
    my $lang_tag = _locale()->language_tag() || 'en';
    return "${AVAILABLE_APPLICATIONS_CACHE}_${lang_tag}_${theme}";
}

=head2 C<flatten_available_applications(APPLICATIONS)>

Convert the application data structure returned by Cpanel::DynamicUI::App::get_available_applications
so its suitable for use by the home page JavaScript applications.

=head3 Arguments

=over

=item APPLICATIONS - hash ref

See Cpanel::DynamicUI::App::get_available_applications

=back

=head3 Returns

Array Ref with Hash Ref elements with the following properties:

=over

=item name - string

Display name of the item

=item searchText - string

Search text that can be used to find this item.

=item url - string

Url to the interface that implements this item.

=item url_is_absolute - boolean

Has the value of 1 if the the "url" property is an absolute URL; 0 otherwise.

=item target - string - optional

=item category - string

The application group's `desc` in DynamicUI. (https://documentation.cpanel.net/display/DD/Guide+to+cPanel+Plugins+-+The+dynamicui+Files)

=item description - string

The application's description in DynamicUI.

=back

=head3 Exceptions

=cut

sub flatten_available_applications {
    my ($applications) = @_;

    return map {
        my $category = $_->{'desc'};
        map {
            my $first_url_char = substr $_->{'url'}, 0, 1;
            {
                key             => $_->{'file'},
                name            => $_->{'itemdesc'},
                searchText      => $_->{'searchtext'},
                url             => $_->{'url'},
                url_is_absolute => ( $first_url_char eq '/' ? 1 : 0 ),
                $_->{'target'} ? ( target => $_->{'target'} ) : (),
                category    => $category,
                description => $_->{'description'},
            }
        } @{ $_->{'items'} }
    } @{ $applications->{'groups'} };

}

=head2 C<get_application_from_available_applications(APPLICATIONS, APPLICATION_NAME)>

Lookup a particular application in the data structure returned by
Cpanel::DynamicUI::App::get_available_applications

=head3 Arguments

=over

=item APPLICATIONS

See Cpanel::DynamicUI::App::get_available_applications for details.

=item APPLICATION_NAME - string

Name of the application to lookup in the APPLICATIONS structure.

=back

=head3 Returns

Hash Ref|Undef - Nothing if the application is not in the APPLICATIONS
structure or the full application sub element in APPLICATIONS->{groups}...{items}...
if it exists.

=cut

sub get_application_from_available_applications {
    my ( $applications, $application_name ) = @_;
    return if !$application_name;
    my $position = $applications->{'index'}->{$application_name} or return;
    return $applications->{'groups'}->[ $position->[0] ]->{'items'}->[ $position->[1] ];
}

=head2 C<get_implementer_from_available_applications(APPLICATIONS, IMPLEMENTER)>

Gets the application by its IMPLIMENTER. An implementer is a secondary lookup
mechanism for finding an application in the APPLICATIONS list.

=head3 Arguments

=over

=item APPLICATIONS

See Cpanel::DynamicUI::App::get_available_applications for details.

=item IMPLEMENTER - string

An alternative name for an application as listed in the 'implements'
lookup index.

=back

=head3 Returns

Hash Ref|Undef - Nothing if the application is not in the APPLICATIONS
structure or the full application sub element in APPLICATIONS->{groups}...{items}...
if it exists.

=cut

sub get_implementer_from_available_applications {
    my ( $applications, $implementer ) = @_;
    return get_application_from_available_applications(
        $applications,
        $applications->{'implements'}{$implementer}
    );
}

1;
