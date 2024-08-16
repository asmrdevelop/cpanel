package Whostmgr::ACLS;

# cpanel - Whostmgr/ACLS.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

require 5.014;    # for s///r

use Whostmgr::ACLS::Data ();
use Cpanel::LoadModule   ();
use Cpanel::SV           ();

our %ACL;
my $acls_are_initialized;
my $optional_components;

our $did_dynamic_acl_update = 0;

#Looking for $aclcats? It’s been migrated to a different format.
#Check out Whostmgr::ACLS::Data.
our %default;

my %dynamic_enabled_acls;
my %dynamic_disabled_acls;
my %_acl_compat = ( 'onlyselfandglobalpkgs' => 'viewglobalpackages' );

# IF YOU LOAD THIS MODULE YOU MUST CALL THIS FUNCTION
# Never ever call init_acls() unless
# you trust the value in $ENV{'REMOTE_USER'}
# has been properly authenticated
#
# NOTE: There is a reinitialize_as_user function in Whostmgr::ACLS::Reinit
# to allow root-level users to re-initialize ACLs as a different user.
sub init_acls {

    # DO NOT LOAD THE ACLS WHILE IN THE BUILD PROCESS - call it at run time
    die q[Do not call init_acls at compile time.] if exists $INC{'B/C.pm'};

    # just return success if already loaded
    return 1 if scalar keys %ACL;

    %default = ( map { $_ => 0 } keys %{ Whostmgr::ACLS::Data::ACLS() } );

    if ( !$ENV{'REMOTE_USER'} ) {
        %ACL                  = %default;
        $acls_are_initialized = 1;
        return;
    }
    %ACL                  = %{ _acls() };
    $acls_are_initialized = 1;
    return 1;
}

sub acls_are_initialized {
    return !!$acls_are_initialized;
}

sub _acls {
    my $user_acls;
    if ( $ENV{'REMOTE_USER'} eq 'root' ) {
        $user_acls = { %default, 'all' => 1 };
    }
    else {
        $user_acls = { %default, %{ get_filtered_reseller_privs() } };
    }
    return $user_acls unless length $ENV{'WHM_API_TOKEN_NAME'};

    require Cpanel::Security::Authn::APITokens::whostmgr;
    my $tokens_obj = Cpanel::Security::Authn::APITokens::whostmgr->new( { 'user' => $ENV{'REMOTE_USER'} } );

    # If for some reason we get past the auth layer in cpsrvd, but have an
    # invalid token that does not exist in the user's token datastore
    # then limit that request to the default ACL
    my $token_obj = $tokens_obj->get_token_details_by_name( $ENV{'WHM_API_TOKEN_NAME'} );

    return {%default} unless $token_obj;

    $token_obj->filter_acls($user_acls);

    # These are filtered now.
    return $user_acls;
}

# This will let us alter the resellers acl at runtime without affecting the
#  stored value.  That way dynamic acls values will persist and be available if
#  the component is licensed and 'enabled' in the future, otherwise we can
#  trump the reseller acl because hasroot as 'disabled' the component, or if it
#  is currently not licensed
sub get_filtered_reseller_privs {
    require Cpanel::Reseller;                            #was add like this in case 43216?
    my $privs = Cpanel::Reseller::get_one_reseller_privs( $ENV{'REMOTE_USER'} );
    if ( $privs->{'all'} ) { return { 'all' => 1 }; }    # no need to check anything else
    my ($d_d_acls) = ( get_dynamic_acl_lists() )[1];
    foreach my $software ( keys %{$d_d_acls} ) {
        foreach my $item ( @{ $d_d_acls->{$software} } ) {
            $privs->{ $item->{'acl'} } = 0 if exists $privs->{ $item->{'acl'} };
        }
    }
    $privs->{'viewglobalpackages'} = $privs->{'onlyselfandglobalpkgs'}
      if exists $privs->{'onlyselfandglobalpkgs'};
    return $privs;
}

# primary key correlates to component name
sub _dynamic_acl_items {
    require Cpanel::Config::ConfigObj;
    my $so   = Cpanel::Config::ConfigObj->new();
    my $data = $so->call_all('acl_desc');
    return $data || {};
}

sub get_dynamic_acl_lists {
    _dynamic_acl_update() if !$did_dynamic_acl_update;
    return _get_dynamic_acl_lists();
}

sub _get_dynamic_acl_lists {
    return ( \%dynamic_enabled_acls, \%dynamic_disabled_acls ) if %dynamic_enabled_acls && %dynamic_disabled_acls && scalar keys %ACL;
    ( %dynamic_enabled_acls, %dynamic_disabled_acls ) = ( (), () );

    require Whostmgr::ACLS::Cache;
    my $cached_data = Whostmgr::ACLS::Cache::load_dynamic_acl_cache_if_current();
    if ( ref $cached_data eq 'ARRAY' && ref $cached_data->[0] eq 'HASH' && ref $cached_data->[1] eq 'HASH' ) {
        %dynamic_enabled_acls  = %{ $cached_data->[0] };
        %dynamic_disabled_acls = %{ $cached_data->[1] };
        return ( \%dynamic_enabled_acls, \%dynamic_disabled_acls );
    }

    my $d_acls = _dynamic_acl_items();

    Cpanel::LoadModule::load_perl_module('Cpanel::Component');
    $optional_components ||= Cpanel::Component->init();
    my $components = $optional_components->get_components();

    # no licensed components: then we turn everything on since nothing requires a license
    if ( !scalar keys %{$components} ) {
        %dynamic_enabled_acls = %{$d_acls};
        local $@;
        eval { Whostmgr::ACLS::Cache::write_dynamic_acl_cache( [ \%dynamic_enabled_acls, \%dynamic_disabled_acls ] ); };
        return ( \%dynamic_enabled_acls, \%dynamic_disabled_acls );
    }

    # filter list for which components are currently 'enabled'
    my %dynamic_filter = %{ $optional_components->get_component_configured_status( keys %{$components} ) };

    foreach ( keys %{$d_acls} ) {

        # Only filter acls that have a license component
        if ( $components->{$_} && !$dynamic_filter{$_} ) {

            # hasroot says no one (including self) should see/use component
            #  hasroot should always have access to 'enable' the component
            #  (affectly skipping this block) thru the 'manage additional
            #  software' which is governed by the license/component
            #  relationship
            $dynamic_disabled_acls{$_} = $d_acls->{$_};
        }
        else {
            $dynamic_enabled_acls{$_} = $d_acls->{$_};
        }
    }

    local $@;
    eval { Whostmgr::ACLS::Cache::write_dynamic_acl_cache( [ \%dynamic_enabled_acls, \%dynamic_disabled_acls ] ); };
    return ( \%dynamic_enabled_acls, \%dynamic_disabled_acls );
}

sub _dynamic_acl_update {
    $did_dynamic_acl_update = 1;

    my ($d_e_acls) = ( _get_dynamic_acl_lists() )[0];

    # no dynamic components to inject
    return 1 if ( !scalar keys %{$d_e_acls} );

    # build dynamic aclcat which controls what is rendered in privs page
    #  and what can be saved. Also populate the default hash
    foreach my $component ( keys %{$d_e_acls} ) {
        foreach my $acl ( @{ $d_e_acls->{$component} } ) {
            Whostmgr::ACLS::Data::add_additional(
                title => $acl->{'acl_subcat'},
                acls  => [
                    {
                        key   => $acl->{'acl'},
                        title => $acl->{'name'},
                    },
                ],
            );

            $default{ $acl->{'acl'} } = $acl->{'default_value'};
        }
    }

    return 1;
}

sub checkacl {
    return 0 if !length( $_[0] );
    if ( $ACL{'all'} ) {

        # Root privilige supersedes all other priviliges.
        # However, some acls are trumped by licensed software components.
        if ( index( $_[0], 'software-' ) == 0 && $_[0] =~ m/^software-(.*)/ ) {
            return exists( ( get_dynamic_acl_lists() )[1]{$1} ) ? 0 : 1;
        }
        return 1;
    }
    return ( exists $ACL{ ( $_acl_compat{ $_[0] } || $_[0] ) } && $ACL{ ( $_acl_compat{ $_[0] } || $_[0] ) } ) ? 1 : 0;
}

*xml_checkacl = \&checkacl;

sub save_acl_list {
    my %OPTS = @_;

    if (   $OPTS{'acllist'} !~ /\(/
        && $OPTS{'acllist'} !~ /\.\./
        && $OPTS{'acllist'} !~ /\//
        && $OPTS{'acllist'} ne '' ) {

        my $acllist = Cpanel::SV::untaint( $OPTS{'acllist'} );

        # CPANEL-34452: In order to allow the saveacllist API call to use
        # 3rd-party ACLs, ensure that these are loaded into %default:
        _dynamic_acl_update() if !$did_dynamic_acl_update;

        require Cpanel::ConfigFiles;
        if ( !-e $Cpanel::ConfigFiles::ACL_LISTS_DIR ) {
            mkdir( $Cpanel::ConfigFiles::ACL_LISTS_DIR, 0755 );
        }
        if ( open( my $acl_fh, ">", "$Cpanel::ConfigFiles::ACL_LISTS_DIR/$acllist" ) ) {
            foreach my $key ( sort keys %Whostmgr::ACLS::default ) {
                if ( defined $OPTS{"acl-${key}"} && $OPTS{"acl-${key}"} eq "1" ) {
                    print {$acl_fh} "${key}=1\n";
                }
                else {
                    print {$acl_fh} "${key}=0\n";
                }
            }
            close($acl_fh);
            return ( 1, "ACL List $acllist saved." );
        }
    }
    return ( 0, "The ACL List could not be saved." );
}

sub list_acls {
    my $list = shift;
    my %ACLLIST;
    require Cpanel::ConfigFiles;
    if ( opendir( my $acl_dir, $Cpanel::ConfigFiles::ACL_LISTS_DIR ) ) {
        while ( my $acl = readdir($acl_dir) ) {
            next if ( $acl =~ /^\.+$/ );
            if ( $list && $list ne '' && $list ne $acl ) { next(); }
            if ( open( my $acl_fh, '<', "$Cpanel::ConfigFiles::ACL_LISTS_DIR/$acl" ) ) {
                $ACLLIST{$acl} = { map { split /=/, $_, 2 } grep { !/^\s*$/ } map { s/\n//r } readline($acl_fh) };
                close($acl_fh);
            }
        }
        closedir($acl_dir);
    }

    return \%ACLLIST;
}

# when saving an ACLs list
#   invalid keys are automatically removed
#   but we could want to force update all, when removing an ACL from the system
sub remove_acls_from_lists {
    my (@to_remove) = @_;
    return unless scalar @to_remove;

    my %default = %Whostmgr::ACLS::default;
    foreach my $acl (@to_remove) {
        delete $default{$acl};
    }

    # avoid a race condition when ACLs are already initialized
    local %Whostmgr::ACLS::default = %default;

    my $lists = list_acls();
    return unless $lists && keys %$lists;

    my $ok = 1;
    foreach my $acllist ( keys %$lists ) {
        my $list = $lists->{$acllist};
        my %save = ( acllist => $acllist, map { "acl-" . $_ => $list->{$_} } keys %$list );
        my ( $success, $msg ) = save_acl_list(%save);
        $ok = $ok && $success;
    }

    return $ok;
}

#XXX: NOTE: This returns true EVEN IN DEMO MODE.
sub hasroot {
    return $ACL{'all'} ? 1 : 0;
}

sub user_has_root {
    my ($user) = @_;

    local %Whostmgr::ACLS::ACL;
    local $ENV{'REMOTE_USER'} = $user;
    Whostmgr::ACLS::init_acls();
    return Whostmgr::ACLS::hasroot();
}

sub acl_compat {
    return $_acl_compat{ $_[0] } || $_[0];
}

# For tests
sub clear_acls {
    %ACL                  = ();
    $acls_are_initialized = undef;
    return 1;
}

1;
