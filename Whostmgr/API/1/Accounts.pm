package Whostmgr::API::1::Accounts;

# cpanel - Whostmgr/API/1/Accounts.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Accounts - WHM API functions for managing cPanel user accounts

=cut

use Cpanel::Imports;

use Cpanel::APICommon::Persona ();    ## PPI NO PARSE - mis-parse constant
use Cpanel::Exception          ();
use Cpanel::LoadModule         ();
use Whostmgr::API::1::Utils    ();
use Whostmgr::ACLS             ();
use Whostmgr::Authz            ();

use Try::Tiny;

use constant ARGUMENT_NEEDS_PARENT => {
    changepackage => 'user',
    modifyacct    => 'user',
    removeacct    => [ 'user', 'username' ],
    editquota     => 'user',
    suspendacct   => 'user',
    unsuspendacct => 'user',
};

use constant NEEDS_ROLE => {
    accountsummary                    => undef,
    changepackage                     => undef,
    _getpkgextensionform              => undef,
    createacct                        => undef,
    domainuserdata                    => undef,
    editquota                         => undef,
    forcepasswordchange               => undef,
    listaccts                         => undef,
    list_users                        => undef,
    listsuspended                     => undef,
    listlockedaccounts                => undef,
    modifyacct                        => undef,
    massmodifyacct                    => undef,
    removeacct                        => undef,
    untrack_acct_id                   => undef,
    verify_user_has_feature           => undef,
    add_override_features_for_user    => undef,
    remove_override_features_for_user => undef,
    setsiteip                         => undef,
    suspendacct                       => undef,
    unsuspendacct                     => undef,
    get_password_strength             => undef,
    get_users_authn_linked_accounts   => undef,
    unlink_user_authn_provider        => undef,
    link_user_authn_provider          => undef,
    get_domain_info                   => undef,
    getdomainowner                    => undef,
    get_current_users_count           => undef,
    get_maximum_users                 => undef,

    hold_outgoing_email      => 'MailSend',
    release_outgoing_email   => 'MailSend',
    suspend_outgoing_email   => 'MailSend',
    unsuspend_outgoing_email => 'MailSend',

    get_homedir_roots => undef,

    set_service_proxy_backends       => undef,
    unset_all_service_proxy_backends => undef,
    get_service_proxy_backends       => undef,

    get_upgrade_opportunities => undef,

    PRIVATE_createacct_child      => undef,
    PRIVATE_set_child_workloads   => undef,
    PRIVATE_unset_child_workloads => undef,
};

sub get_service_proxy_backends ( $args, $metadata, @ ) {

    # IMPORTANT: If this API is ever opened up to non-root access,
    # we MUST verify the caller’s access to the user.
    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );

    require Cpanel::AccountProxy::Storage;
    my $payload = Cpanel::AccountProxy::Storage::get_service_proxy_backends_for_user($username);

    $metadata->set_ok();

    return { payload => $payload };
}

sub unset_all_service_proxy_backends ( $args, $metadata, @ ) {

    # IMPORTANT: If this API is ever opened up to non-root access,
    # we MUST verify the caller’s access to the user.
    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );

    {
        require Cpanel::AccountProxy::Transaction;
        local $SIG{'__WARN__'} = sub { $metadata->add_warning(shift) };

        Cpanel::AccountProxy::Transaction::unset_all_backends_and_update_services($username);
    }

    $metadata->set_ok();

    return;
}

sub set_service_proxy_backends ( $args, $metadata, @ ) {

    # IMPORTANT: If this API is ever opened up to non-root access,
    # we MUST verify the caller’s access to the user.
    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );

    my @args_kv;

    if ( my $backend = Whostmgr::API::1::Utils::get_length_argument( $args, 'general' ) ) {
        push @args_kv, ( backend => $backend );
    }

    my @worker_types    = Whostmgr::API::1::Utils::get_length_arguments( $args, 'service_group' );
    my @worker_backends = Whostmgr::API::1::Utils::get_length_arguments( $args, 'service_group_backend' );

    if ( @worker_types != @worker_backends ) {
        die "Count of “service_group” (@worker_types) mismatches “service_group_backend” (@worker_backends)!\n";
    }

    if (@worker_types) {
        require Cpanel::AccountProxy::Storage;
        Cpanel::AccountProxy::Storage::validate_proxy_backend_types_or_die( \@worker_types );

        my %worker_backend;
        push @args_kv, ( worker => \%worker_backend );

        @worker_backend{@worker_types} = @worker_backends;
    }

    if (@args_kv) {
        require Cpanel::AccountProxy::Transaction;

        local $SIG{'__WARN__'} = sub { $metadata->add_warning(shift) };

        Cpanel::AccountProxy::Transaction::set_backends_and_update_services(
            username => $username,
            @args_kv,
        );
    }

    $metadata->set_ok();

    return;
}

sub accountsummary {
    my ( $args, $metadata ) = @_;
    my $acct_list;

    if ( !exists $args->{'user'} && !exists $args->{'domain'} ) {
        die "You must specify a user or domain to get a summary of.\n";
    }

    if ( exists $args->{'user'} ) {
        $args->{'searchtype'}   = 'user';
        $args->{'searchmethod'} = 'exact';
        $args->{'search'}       = $args->{'user'};
    }
    else {
        $args->{'searchtype'}   = 'domain';
        $args->{'searchmethod'} = 'exact';
        $args->{'search'}       = $args->{'domain'};
    }

    require Whostmgr::Accounts::List;
    ( my $count, $acct_list ) = Whostmgr::Accounts::List::listaccts(%$args);

    if ( ref $acct_list eq 'ARRAY' ) {
        require Cpanel::NAT;
        foreach my $acct (@$acct_list) {
            $acct->{'ip'} = Cpanel::NAT::get_public_ip( $acct->{'ip'} );
        }
    }

    if ($count) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Account does not exist.';
    }

    return { 'acct' => $acct_list };
}

sub changepackage {
    my ( $args, $metadata ) = @_;

    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );
    my $package  = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'pkg' );

    require Cpanel::LinkedNode::Worker::WHM::Accounts;
    my ( $result, $reason, $rawout ) = Cpanel::LinkedNode::Worker::WHM::Accounts::change_account_package( $username, $package );
    $result ? $metadata->set_ok() : $metadata->set_not_ok($reason);
    $metadata->{'output'}->{'raw'} = $rawout if length $rawout;
    return;
}

sub _getpkgextensionform {
    my ( $args, $metadata ) = @_;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    # Return nothing
    require Whostmgr::Packages::Load;
    my $package_extension_dir = Whostmgr::Packages::Load::package_extensions_dir();
    return {} unless -d $package_extension_dir;

    # Find the package and fail if we don't have access to it.
    my $pkg = $args->{'pkg'};
    require Whostmgr::Packages::Fetch;
    my $packages = Whostmgr::Packages::Fetch::fetch_package_list( "want" => "creatable", 'package' => $pkg );
    if ( !$pkg || !$packages->{$pkg} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Package $pkg not found!";
        return {};
    }

    # Return empty if we don't have any extensions
    my $package    = $packages->{$pkg};
    my @extensions = split( m/\s+/, $package->{_PACKAGE_EXTENSIONS} || '' );
    return {} if ( !@extensions );    # No HTML if no package.

    # Get the H3. name of all the extensions
    my ($extension_info) = Whostmgr::Packages::Load::get_all_package_extensions();

    Cpanel::LoadModule::load_perl_module('Cpanel::Template');

    my $html;
    foreach my $ext (@extensions) {
        my $template_file = "$package_extension_dir/$ext.tt2";

        if ( !-f $template_file ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = "Template for extension $ext not found!";
            return { 'html' => "<h3>Template for extension $ext not found!</h3>" };
        }

        my $output = Cpanel::Template::process_template(
            'whostmgr',
            {
                template_file => "$package_extension_dir/$ext.tt2",
                'data'        => { 'defaults' => $package }
            }
        );
        next unless $output;
        next unless ref $output eq 'SCALAR';

        $output = $$output;

        # TODO Extension name isn't locallized here!
        $output = "<h3>$extension_info->{$ext}</h3>\n$output";

        my $open_box  = qq{<div class="fatBorder" id="${ext}_Extension">\n<fieldset class="groupEditor">\n<div class="propertyGroup">\n};
        my $close_box = qq{</div>\n</fieldset>\n</div>\n};
        $html .= $open_box . $output . "$close_box";
    }

    return { 'html' => $html };
}

sub createacct ( $args, $metadata, @xtra ) {

    # Throw on this parameter specifically in case someone tries to
    # set up a child account with the plain createacct call.
    if ( $args->{'child_workloads'} ) {
        die "Invalid parameter: child_workloads\n";
    }

    return _createacct( $args, $metadata, @xtra );
}

sub PRIVATE_createacct_child ( $args, $metadata, @xtra ) {
    my @workloads = Whostmgr::API::1::Utils::get_length_arguments( $args, 'child_workloads' );
    die "Need >=1 “child_workloads”!\n" if !@workloads;

    die "Child accounts cannot be resellers.\n" if $args->{'reseller'};

    local $args->{'child_workloads'} = \@workloads;

    # All child-component accounts are root-owned.
    local $args->{'owner'} = 'root';

    local $args->{'skip_password_strength_check'} = 1;

    return _createacct( $args, $metadata, @xtra );
}

sub _createacct {
    my ( $args, $metadata ) = @_;

    if ( !Whostmgr::ACLS::hasroot() ) {
        for my $root_only_arg (qw( force  forcedns  is_restore mailbox_format)) {
            if ( $args->{$root_only_arg} ) {
                die Cpanel::Exception->new( "You cannot use the “[_1]” argument because you do not have root access.", [$root_only_arg] );
            }
        }

        if ( $args->{'owner'} && $args->{'owner'} ne $ENV{'REMOTE_USER'} ) {
            die Cpanel::Exception->new("Without root access, you can only create accounts that you yourself own.");
        }
    }

    my @enhancements = Whostmgr::API::1::Utils::get_arguments( $args, 'account_enhancements' );
    $args->{'account_enhancements'} = \@enhancements if scalar @enhancements;

    my $given_ip = $args->{'customip'};
    require Cpanel::NAT;
    $args->{'customip'} = Cpanel::NAT::get_local_ip( $args->{'customip'} );
    require Whostmgr::Accounts::Create;

    my ( $result, $reason, $output, $opref ) = Whostmgr::Accounts::Create::_createaccount(%$args);

    if ( $args->{'customip'} ) {
        $output =~ s/$args->{'customip'}/$given_ip/g;
        $output ||= undef;
    }

    $metadata->{'result'}          = $result ? 1 : 0;
    $metadata->{'reason'}          = $reason;
    $metadata->{'output'}->{'raw'} = $output;

    if ($result) {
        $opref->{'ip'} = Cpanel::NAT::get_public_ip( $opref->{'ip'} );
        return $opref;
    }

    return;
}

=head2 PRIVATE_set_child_workloads()

This provides an API layer around L<Cpanel::LinkedNode::ChildWorkloads>’s
C<set()>.

Args are:

=over

=item * C<username> - The username whose cpuser data to update.

=item * C<workload> (multiple) - The workloads to set as the ones that
the user’s local account implements.

=back

The return is a hashref of:

=over

=item * C<updated> - A boolean that indicates whether a change was made
to the cpuser data. (Falsy means that the cpuser data was already in the
desired state.)

=back

=cut

sub PRIVATE_set_child_workloads ( $args, $metadata, @ ) {
    my $username  = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );
    my @workloads = Whostmgr::API::1::Utils::get_length_required_arguments( $args, 'workload' );

    require Cpanel::LinkedNode::ChildWorkloads;
    require Cpanel::LinkedNode::AccountCache;
    require Cpanel::PromiseUtils;
    require Cpanel::CommandQueue;

    my $cq = Cpanel::CommandQueue->new();

    my $old_workloads_ar;

    $cq->add(
        sub {
            $old_workloads_ar = Cpanel::LinkedNode::ChildWorkloads::set( $username, @workloads );
        },
        sub {
            if (@$old_workloads_ar) {
                Cpanel::LinkedNode::ChildWorkloads::set( $username, @$old_workloads_ar );
            }
            else {
                Cpanel::LinkedNode::ChildWorkloads::unset($username);
            }
        },
        'restore former workloads, if any',
    );

    $cq->add(
        sub {
            if ($old_workloads_ar) {
                my $p = Cpanel::LinkedNode::AccountCache->new_p()->then(
                    sub ($cache) {
                        $cache->set_user_child_workloads( $username, @workloads );
                        return $cache->save_p();
                    },
                );

                Cpanel::PromiseUtils::wait_anyevent($p);
            }
        },
    );

    $cq->run();

    $metadata->set_ok();

    return { updated => $old_workloads_ar ? 1 : 0 };
}

=head2 PRIVATE_unset_child_workloads()

This provides an API layer around L<Cpanel::LinkedNode::ChildWorkloads>’s
C<unset()>.

Args are:

=over

=item * C<username> - The username whose cpuser data to update.

=back

The return is a hashref of:

=over

=item * C<updated> - A boolean that indicates whether a change was made
to the cpuser data. (Falsy means that the cpuser data was already in the
desired state.)

=back

=cut

sub PRIVATE_unset_child_workloads ( $args, $metadata, @ ) {
    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );

    require Cpanel::LinkedNode::ChildWorkloads;
    require Cpanel::LinkedNode::AccountCache;
    require Cpanel::PromiseUtils;
    require Cpanel::CommandQueue;

    my $cq = Cpanel::CommandQueue->new();

    my $old_workloads_ar;

    $cq->add(
        sub {
            $old_workloads_ar = Cpanel::LinkedNode::ChildWorkloads::unset($username);
        },
        sub {
            if (@$old_workloads_ar) {
                Cpanel::LinkedNode::ChildWorkloads::set( $username, @$old_workloads_ar );
            }
        },
        'restore former workloads, if any',
    );

    $cq->add(
        sub {
            if ($old_workloads_ar) {
                my $p = Cpanel::LinkedNode::AccountCache->new_p()->then(
                    sub ($cache) {
                        $cache->unset_user_child_workloads($username);
                        return $cache->save_p();
                    },
                );

                Cpanel::PromiseUtils::wait_anyevent($p);
            }
        },
    );

    $cq->run();

    $metadata->set_ok();

    return { updated => $old_workloads_ar && @$old_workloads_ar ? 1 : 0 };
}

sub domainuserdata {
    my ( $args, $metadata ) = @_;
    my $userdata;
    my $domain = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'domain' );

    # verify_domain_access will always die if they do not
    # have access or the user cannot be determined
    my $user = Whostmgr::Authz::verify_domain_access($domain);
    require Cpanel::Config::userdata::Load;
    if ( my $domain_file = Cpanel::Config::userdata::Load::get_real_domain( $user, $domain ) ) {    #this is done to ensure that PARKED domains are properly checked
        $userdata = Cpanel::Config::userdata::Load::load_userdata( $user, $domain_file, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
    }
    if ( !$userdata || !scalar keys %$userdata ) {

        # verify_domain_access() will have thrown if a reseller attempts
        # access to a forbidden domain. Thus, if we get here, we’re always
        # root-ish, so it’s fine to report details of system state like this.
        die Cpanel::Exception::create( 'DomainDoesNotExist', [ name => $domain ] );
    }
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'userdata' => $userdata };
}

sub editquota {
    my ( $args, $metadata ) = @_;
    my $user = $args->{'user'};

    Whostmgr::Authz::verify_account_access($user);

    my $quota = $args->{'quota'};

    if ( $quota !~ m/^(unlimited)|(\d+)$/ ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Invalid value ($quota) for quota supplied.";
        return;
    }

    require Whostmgr::Quota;
    my ( $result, $reason, $output ) = Whostmgr::Quota::setusersquota( $user, $quota );
    $metadata->{'result'} = $result ? 1 : 0;
    $metadata->{'reason'} = $reason || ( $result ? 'OK' : 'Failed to set quota.' );
    if ( length $output ) {
        $metadata->{'output'}->{'raw'} = $output;
    }
    return;
}

sub forcepasswordchange {
    my ( $args, $metadata ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::ForcePassword');
    my $users_json = Whostmgr::API::1::Utils::get_required_argument( $args, 'users_json' );

    require Cpanel::JSON;
    my $users_hr = Cpanel::JSON::Load($users_json);

    my $error;

    my $return_value;

    my $hasroot = Whostmgr::ACLS::hasroot();

    my @invalid;
    require Cpanel::Validate::Username;

    if ($hasroot) {
        @invalid = grep { !Cpanel::Validate::Username::is_valid($_) } keys %$users_hr;
    }
    else {
        require Whostmgr::AcctInfo;
        my $owned_hr = Whostmgr::AcctInfo::getaccts( $ENV{'REMOTE_USER'} );
        @invalid = grep { !$owned_hr->{$_} || !Cpanel::Validate::Username::is_valid($_) } keys %$users_hr;
    }

    if (@invalid) {
        $error = "Invalid user(s): " . join( ', ', @invalid );
    }
    else {
        require Cpanel::LinkedNode::List;
        my $child_accts_ar = Cpanel::LinkedNode::List::list_user_workloads();
        my %is_child       = map { $_->{'user'} => undef } @$child_accts_ar;

        my @children = grep { exists $is_child{$_} } keys %$users_hr;

        if (@children) {
            $error = join ', ', @children;
            $error = "Cannot set for child account(s): $error";
        }
    }

    if ( !$error ) {
        my ( $already_hr, $errs_hr ) = Cpanel::ForcePassword::get_force_password_flags_picky( [ keys %$users_hr ], { stop_on_failure => 1 } );

        my $err = ( keys %$errs_hr )[0];
        if ( length $err ) {
            $error = $err;
        }
        else {
            for my $user ( keys %$users_hr ) {
                delete $users_hr->{$user} if !!$users_hr->{$user} eq !!$already_hr->{$user};
            }
            if ( keys %$users_hr ) {
                my ( $successes_ar, $failures_hr ) = Cpanel::ForcePassword::update_force_password_flags_picky( $users_hr, { stop_on_failure => $args->{'stop_on_failure'} } );
                $return_value = { updated => $successes_ar };

                my $failed_user = ( keys %$failures_hr )[0];
                if ($failed_user) {
                    $return_value->{'failed'} = $failures_hr;

                    if ( $args->{'stop_on_failure'} || ( scalar keys %$failures_hr ) == 1 ) {
                        $error = $failures_hr->{$failed_user};
                    }
                    else {
                        $error = 'Force password change flags for the following users could not be updated: ' . join( ', ', sort keys %$failures_hr );
                    }
                }

            }
            else {
                @{$metadata}{ 'result', 'reason' } = ( 1, 'Nothing to do.' );
                return;
            }
        }
    }

    @{$metadata}{ 'result', 'reason' } = $error ? ( 0, $error ) : ( 1, 'OK' );

    return $return_value || ();
}

sub listaccts {
    my ( $args, $metadata ) = @_;
    if ( exists $args->{'searchtype'} && $args->{'searchtype'} !~ m/^(domain|ip|user|package|owner|domain_and_user)$/ ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Unknown search type.';
        return;
    }

    my $want = defined $args->{'want'} ? [ split /,/, $args->{'want'} ] : undef;

    require Whostmgr::Accounts::List;
    my ( $count, $account_list_ref ) = Whostmgr::Accounts::List::listaccts(%$args);

    if ( ref $account_list_ref eq 'ARRAY' ) {
        require Cpanel::NAT;
        require Cpanel::Backup::MetadataDB::Tiny;
        foreach my $acct (@$account_list_ref) {
            $acct->{'ip'}         = Cpanel::NAT::get_public_ip( $acct->{'ip'} );
            $acct->{'has_backup'} = Cpanel::Backup::MetadataDB::Tiny::does_user_have_a_backup( $acct->{'user'} );

            # All user data must be assigned before this line to ensure only “want” params are returned.
            $acct = { map { $_ => $acct->{$_} } @$want } if defined $want;
        }
    }

    $metadata->{'result'} = defined $count        ? 1    : 0;
    $metadata->{'reason'} = $metadata->{'result'} ? 'OK' : 'No accounts found.';
    return if !$count;
    return { 'acct' => $account_list_ref };
}

sub list_users {
    my ( $args, $metadata ) = @_;

    my @users = _get_users_accessible_by_logged_in_user();

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'users' => \@users };
}

#NOTE: Overridden in tests
sub _get_users_accessible_by_logged_in_user {
    my $hasroot           = Whostmgr::ACLS::hasroot();
    my $can_see_all_accts = $hasroot || ( $ENV{'REMOTE_USER'} eq 'root' && Whostmgr::ACLS::checkacl('list-accts') );

    my $logged_in_user = $ENV{'REMOTE_USER'};
    require Whostmgr::AcctInfo;
    my $user_owner_hr = Whostmgr::AcctInfo::get_accounts(
        ( $can_see_all_accts ? () : $logged_in_user ),
    );

    $user_owner_hr->{$logged_in_user} ||= 1;

    if ($hasroot) {
        $user_owner_hr->{'root'} = 1;
    }

    return keys %$user_owner_hr;
}

sub listsuspended {
    my ( undef, $metadata ) = @_;
    require Whostmgr::Accounts::List;
    my $rsdref = Whostmgr::Accounts::List::listsuspended();
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'account' => $rsdref };
}

sub listlockedaccounts {
    my ( undef, $metadata ) = @_;
    require Whostmgr::Accounts::List;
    my $locked_accounts = Whostmgr::Accounts::List::getlockedlist();
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'account' => $locked_accounts };
}

sub modifyacct {
    my ( $args, $metadata ) = @_;

    if ( !exists $args->{'user'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Must at least specify a user to modify.';
        return;
    }

    Whostmgr::Authz::verify_account_access( $args->{'user'} );

    delete $args->{'status_callback'};
    if ( exists $args->{'CPTHEME'} && !exists $args->{'RS'} ) {
        $args->{'RS'} = $args->{'CPTHEME'};
    }

    # support legacy LANG key
    if ( !exists $args->{'LOCALE'} || !$args->{'LOCALE'} && exists $args->{'LANG'} ) {
        require Cpanel::Locale::Utils::Legacy;
        $args->{'LOCALE'} = Cpanel::Locale::Utils::Legacy::map_any_old_style_to_new_style( $args->{'LANG'} );
    }

    $args->{'account_enhancements'} = [ Whostmgr::API::1::Utils::get_arguments( $args, 'account_enhancements' ) ];

    Cpanel::LoadModule::load_perl_module('Whostmgr::Accounts::Modify');    # hide from t/00_check_module_ship.t
    my ( $status, $statusmsg, $messages, $warnings, $newcfg ) = Whostmgr::Accounts::Modify::modify(%$args);
    $metadata->{'result'}               = $status ? 1 : 0;
    $metadata->{'reason'}               = $statusmsg;
    $metadata->{'output'}->{'messages'} = $messages;
    $metadata->{'output'}->{'warnings'} = $warnings;
    return $newcfg if $status;
    return;
}

sub massmodifyacct {
    my ( $args, $metadata, $api_opts_hr ) = @_;

    my @users = Whostmgr::API::1::Utils::get_length_required_arguments( $args, "user" );

    my %opts;
    $opts{$_} = $args->{$_} for grep { index( $_, "user-" ) != 0 } keys %$args;

    my $persona = $api_opts_hr->{'persona'};
    if ( $persona && $persona eq Cpanel::APICommon::Persona::PARENT ) {
        $opts{'on_child'} = 'permit';
    }

    # Do not allow this key in the massmodifyacct call until
    # 'scripts/update_existing_mail_quotas_for_account' has been optimized
    delete $opts{update_existing_email_account_quotas};

    require Whostmgr::Accounts::Modify;
    my $results_hr = Whostmgr::Accounts::Modify::mass_modify( \@users, %opts );

    my ( $any_errors, @ordered_results );

    foreach my $user ( keys %{ $results_hr->{users} } ) {
        foreach my $modification ( @{ $results_hr->{users}{$user} } ) {
            push @ordered_results, { %$modification, user => $user };
            $any_errors ||= !$modification->{result};
        }
    }

    if ( !$any_errors ) {
        $metadata->set_ok();
    }
    else {
        $metadata->set_not_ok("Failed to modify one or more users.");
    }

    $metadata->{messages} = $results_hr->{messages};
    $metadata->{warnings} = $results_hr->{warnings};

    return { payload => \@ordered_results };
}

sub removeacct ( $args, $metadata, $api_opts_hr, @ ) {    ## no critic qw(ManyArgs)

    local $args->{'user'} = $args->{'user'} || $args->{'username'};

    Whostmgr::Authz::verify_account_access( $args->{'user'} );

    require Whostmgr::Accounts::Remove;
    $args->{'keepdns'} = ( length $args->{'keepdns'} && $args->{'keepdns'} =~ /[y1]/ ) ? 1 : 0;

    require Cpanel::WarnAgain;

    my @warnings;
    my $warn_catcher = Cpanel::WarnAgain->new_to_array( \@warnings );

    my $persona = $api_opts_hr->{'persona'};
    if ( $persona && $persona eq Cpanel::APICommon::Persona::PARENT ) {
        $args->{'if_child'} = 'remove';
    }

    my ( $result, $reason, $output ) = Whostmgr::Accounts::Remove::_removeaccount(%$args);

    $metadata->{'result'} = $result ? 1 : 0;
    $metadata->{'reason'} = $reason;

    $metadata->add_warning($_) for @warnings;

    $metadata->{'output'}->{'raw'} = $output;
    return;
}

sub untrack_acct_id {
    my ( $args, $metadata ) = @_;

    if ( !Whostmgr::ACLS::hasroot() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'You cannot untrack IDs because you do not have root access.';
        return;
    }

    require Whostmgr::Accounts::IdTrack;
    require AcctLock;

    my $lock = AcctLock::create();

    my ( $result, $reason ) = Whostmgr::Accounts::IdTrack::remove_id(%$args);
    $metadata->{'result'} = $result ? 1 : 0;
    $metadata->{'reason'} = $reason;
    return;
}

=head2 hold_outgoing_email

=head3 Purpose

Force deferring all outgoing mail for a user and their
subaccounts. All new outgoing messages sent by the user and
messages already in the mail queue will be deferred.

=head3 Arguments

    - $args - {
            'user' - A cPanel user
        }


=head3 Output

    none

=cut

sub hold_outgoing_email {
    my ( $args, $metadata, $api_args ) = @_;

    # Do this first because tests expect it.
    my $user = _get_and_verify_user_arg($args);

    if ( _looks_like_cpusername($user) ) {
        my $remote = _proxy_this_api_call( $args, $metadata, $api_args );
        return $remote->get_remote_data() if $remote;
    }

    require Whostmgr::Accounts::Email;
    Whostmgr::Accounts::Email::hold_outgoing_email( 'user' => $user );
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

sub _looks_like_cpusername ($name) {
    return $name ne 'root' && $name ne 'nobody';
}

sub _get_and_verify_user_arg ($args) {
    my $user = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );

    require Cpanel::AcctUtils::Account;
    Cpanel::AcctUtils::Account::accountexists_or_die($user);
    Whostmgr::Authz::verify_account_access($user);

    return $user;
}

=head2 release_outgoing_email

=head3 Purpose

This removes a hold on the users outgoing mail and
allows any mail in the queue that was sent by the user
or their subaccounts to be processed the next time the
mail queue is run.

=head3 Arguments

    - $args - {
            'user' - A cPanel user
        }


=head3 Output

    none

=cut

sub release_outgoing_email {
    my ( $args, $metadata, $api_args ) = @_;

    # Do this first because tests expect it.
    my $user = _get_and_verify_user_arg($args);

    if ( _looks_like_cpusername($user) ) {
        my $remote = _proxy_this_api_call( $args, $metadata, $api_args );
        return $remote->get_remote_data() if $remote;
    }

    require Whostmgr::Accounts::Email;
    Whostmgr::Accounts::Email::release_outgoing_email( 'user' => $user );
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

=head2 suspend_outgoing_email

=head3 Purpose

Force failure for all outgoing mail send by a user and their
subaccounts. All new outgoing messages sent by the user and
messages already in the mail queue will be forced to fail.

=head3 Arguments

    - $args - {
            'user' - A cPanel user
        }


=head3 Output

    none

=cut

sub suspend_outgoing_email {
    my ( $args, $metadata, $api_args ) = @_;

    # Do this first because tests expect it.
    my $user = _get_and_verify_user_arg($args);

    if ( _looks_like_cpusername($user) ) {
        my $remote = _proxy_this_api_call( $args, $metadata, $api_args );
        return $remote->get_remote_data() if $remote;
    }

    require Whostmgr::Accounts::Email;
    Whostmgr::Accounts::Email::suspend_outgoing_email( 'user' => $user );
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

=head2 unsuspend_outgoing_email

=head3 Purpose

This removes the forced failure setting set by
suspend_outgoing_email for a user and their
subaccounts.

=head3 Arguments

    - $args - {
            'user' - A cPanel user
        }


=head3 Output

    none

=cut

sub unsuspend_outgoing_email {
    my ( $args, $metadata, $api_args ) = @_;

    # Do this first because tests expect it.
    my $user = _get_and_verify_user_arg($args);

    if ( _looks_like_cpusername($user) ) {
        my $remote = _proxy_this_api_call( $args, $metadata, $api_args );
        return $remote->get_remote_data() if $remote;
    }

    require Whostmgr::Accounts::Email;
    Whostmgr::Accounts::Email::unsuspend_outgoing_email( 'user' => $user );
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

sub verify_user_has_feature {
    my ( $args, $metadata ) = @_;

    my $user    = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );
    my $feature = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'feature' );

    Whostmgr::Authz::verify_account_access($user);

    require Cpanel::Features::Check;
    my $has_feature = Cpanel::Features::Check::check_feature_for_user( $user, $feature ) ? 1 : 0;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { has_feature => $has_feature, query_feature => $feature };
}

sub add_override_features_for_user {
    my ( $args, $metadata ) = @_;

    my $user     = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );
    my $features = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'features' );

    Whostmgr::Authz::verify_account_access($user);

    require Cpanel::Features;
    require Cpanel::JSON;
    Cpanel::Features::add_override_features_for_user( $user, Cpanel::JSON::Load($features) );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

sub remove_override_features_for_user {
    my ( $args, $metadata ) = @_;

    my $user     = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );
    my $features = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'features' );

    Whostmgr::Authz::verify_account_access($user);

    require Cpanel::Features;
    require Cpanel::JSON;
    Cpanel::Features::remove_override_features_for_user( $user, Cpanel::JSON::Load($features) );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

# Despite the name, this sets a user’s IP address and doesn’t
# do anything useful with the domain.
sub setsiteip {
    my ( $args, $metadata ) = @_;
    my $user = $args->{'user'};
    require Cpanel::NAT;
    my $ip     = Cpanel::NAT::get_local_ip( $args->{'ip'} );
    my $result = 1;
    my $msg    = "";

    if ( exists $args->{'domain'} ) {
        require Cpanel::AcctUtils::DomainOwner::Tiny;
        $user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $args->{'domain'} );

        if ( exists $args->{'user'} && $user ne $args->{'user'} ) {
            $result = 0;
            $msg    = 'User does not own the domain provided.';
        }
    }

    if ($result) {
        require Whostmgr::Accounts::SiteIP;
        ( $result, $msg ) = Whostmgr::Accounts::SiteIP::set( $user, undef, $ip, 1 );
    }
    if ( $result && !length $msg ) {
        $msg = 'OK';
    }

    $metadata->{'result'} = $result ? 1 : 0;
    $metadata->{'reason'} = $msg;
    return;
}

sub suspendacct {
    my ( $args, $metadata ) = @_;

    Whostmgr::Authz::verify_account_access( $args->{'user'} );

    require Whostmgr::Accounts::Suspension;
    my ( $result, $reason ) = Whostmgr::Accounts::Suspension::suspendacct( $args->{'user'}, $args->{'reason'}, $args->{'disallowun'}, $args->{'leave-ftp-accts-enabled'} );
    $metadata->{'result'} = $result ? 1 : 0;
    if ($result) {
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'reason'} = 'Failed to suspend account.';
    }
    $metadata->{'output'}->{'raw'} = $reason;
    return;
}

sub unsuspendacct {
    my ( $args, $metadata ) = @_;

    Whostmgr::Authz::verify_account_access( $args->{'user'} );

    my $retain_service_proxies = $args->{'retain-service-proxies'} && $args->{'retain-service-proxies'} eq "1";

    require Whostmgr::Accounts::Suspension;
    my ( $result, $reason ) = Whostmgr::Accounts::Suspension::unsuspendacct( $args->{'user'}, $retain_service_proxies );
    $metadata->{'result'} = $result ? 1 : 0;
    if ($result) {
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'reason'} = 'Failed to unsuspend account.';
    }
    $metadata->{'output'}->{'raw'} = $reason;
    return;
}

sub get_password_strength {
    my ( $args, $metadata ) = @_;
    if ( !exists $args->{'password'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'password parameter was not passed';
        return;
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    require Cpanel::PasswdStrength::Check;
    return { 'strength' => Cpanel::PasswdStrength::Check::get_password_strength( $args->{'password'} ) };
}

sub get_users_authn_linked_accounts {
    my ( $args, $metadata ) = @_;

    require Cpanel::Config::LoadUserDomains;
    my $user_to_domains_map = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 0, 1 );
    my $regex_text          = join(
        '|',
        map {
            '^' . quotemeta($_) . '$',
              map { quotemeta( '@' . $_ ) . '$' } @{ $user_to_domains_map->{$_} || [] }
        } _get_users_accessible_by_logged_in_user()
    );
    my $regex = qr/$regex_text/;

    my $provider_protocol = 'openid_connect';
    require Cpanel::Security::Authn::OpenIdConnect;
    my $all_providers_ref = Cpanel::Security::Authn::OpenIdConnect::get_available_openid_connect_providers();
    my @results;
    require Cpanel::Security::Authn::LinkDB;
    foreach my $provider_id ( keys %$all_providers_ref ) {
        my $linkdb = Cpanel::Security::Authn::LinkDB->new( 'protocol' => $provider_protocol, 'provider_name' => $provider_id );
        my $links  = $linkdb->get_links_for_users_matching_regex( 'regex' => $regex );
        foreach my $username ( keys %$links ) {
            foreach my $subject_unique_identifier ( keys %{ $links->{$username} } ) {
                my $subscriber = $links->{$username}{$subject_unique_identifier};
                push @results,
                  {
                    'username'                  => $username,
                    'provider_protocol'         => $provider_protocol,
                    'provider_id'               => $provider_id,
                    'subject_unique_identifier' => $subject_unique_identifier,
                    'link_time'                 => $subscriber->{'link_time'},
                    'preferred_username'        => $subscriber->{'preferred_username'},
                  };
            }
        }
    }
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'username_linked_accounts' => \@results };
}

## Wrapper API for functionality in Cpanel::Security::Authn::User::Modify::remove_authn_link_for_user
sub unlink_user_authn_provider {
    my ( $args, $metadata ) = @_;

    my $username                  = Whostmgr::API::1::Utils::get_required_argument( $args, 'username' );
    my $provider_id               = Whostmgr::API::1::Utils::get_required_argument( $args, 'provider_id' );
    my $subject_unique_identifier = Whostmgr::API::1::Utils::get_required_argument( $args, 'subject_unique_identifier' );

    my $operator = $ENV{'REMOTE_USER'} || die Cpanel::Exception->create_raw('Need $ENV{REMOTE_USER}!');

    require Cpanel::AccessControl;
    Cpanel::AccessControl::user_has_access_to_account( $operator, $username ) or die Cpanel::Exception->create( 'You do not have access to an account named “[_1]”.', [$username] );

    require Cpanel::Security::Authn::User::Modify;
    Cpanel::Security::Authn::User::Modify::remove_authn_link_for_user( $username, 'openid_connect', $provider_id, $subject_unique_identifier );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

## Wrapper API for functionality in Cpanel::Security::Authn::User::Modify::add_authn_link_for_user
sub link_user_authn_provider {
    my ( $args, $metadata ) = @_;

    my $username                  = Whostmgr::API::1::Utils::get_required_argument( $args, 'username' );
    my $provider_id               = Whostmgr::API::1::Utils::get_required_argument( $args, 'provider_id' );
    my $subject_unique_identifier = Whostmgr::API::1::Utils::get_required_argument( $args, 'subject_unique_identifier' );
    my $preferred_username        = Whostmgr::API::1::Utils::get_required_argument( $args, 'preferred_username' );

    my $operator = $ENV{'REMOTE_USER'} || die Cpanel::Exception->create_raw('Need $ENV{REMOTE_USER}!');

    require Cpanel::AccessControl;
    Cpanel::AccessControl::user_has_access_to_account( $operator, $username ) or die Cpanel::Exception->create( 'You do not have access to an account named “[_1]”.', [$username] );

    require Cpanel::Security::Authn::User::Modify;
    Cpanel::Security::Authn::User::Modify::add_authn_link_for_user( $username, 'openid_connect', $provider_id, $subject_unique_identifier, { 'preferred_username' => $preferred_username } );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

=head2 get_domain_info

=head3 Purpose

Provides information about the domains that have
been explictly created by the user/admin on the
server.  This does not include auto created domains
such as 'www' or 'mail'

=head3 Arguments

None

=head3 Output

Returns a hashref with a single 'domains' key in the following
format:

        {
            'domains' => [
                {
                    'docroot'             => '/home/koston/public_html',
                    'user_owner'          => 'root',
                    'ipv4_ssl'            => '208.74.121.125',
                    'modsecurity_enabled' => 1,
                    'ipv4'                => '208.74.121.125',
                    'port_ssl'            => '443',
                    'ipv6_is_dedicated'   => '1',
                    'user'                => 'koston',
                    'ipv6'                => '2001:0db8:1a34:56cf:0000:0000:0000:0001',
                    'php_version'         => 'ea-php99',
                    'domain'              => 'sillycpaneler.org',
                    'parent_domain'       => 'koston.org',
                    'domain_type'         => 'parked',
                    'port'                => '80'
                },
                .....
            ]
        }

=cut

sub get_domain_info {
    my ( $args, $metadata ) = @_;

    require Cpanel::Config::userdata::Cache;
    my $userdata = Cpanel::Config::userdata::Cache::load_cache();

    my $hasroot     = Whostmgr::ACLS::hasroot();
    my $FIELD_OWNER = $Cpanel::Config::userdata::Cache::FIELD_OWNER;
    my $FIELD_USER  = $Cpanel::Config::userdata::Cache::FIELD_USER;
    my @FIELD_NAMES = @Cpanel::Config::userdata::Cache::FIELD_NAMES;

    my ( $version, @controlled_domains );
    require Cpanel::IP::Parse;
    foreach my $domain ( sort keys %$userdata ) {
        my $domain_ref = $userdata->{$domain};
        next if ( !$hasroot && $domain_ref->[$FIELD_OWNER] ne $ENV{'REMOTE_USER'} && $domain_ref->[$FIELD_USER] ne $ENV{'REMOTE_USER'} );
        my %ref = ( 'domain' => $domain );
        @ref{@FIELD_NAMES} = @$domain_ref;
        ( $version, $ref{'ipv4'}, $ref{'port'} )         = Cpanel::IP::Parse::parse( delete $ref{'ip_port'} );
        ( $version, $ref{'ipv4_ssl'}, $ref{'port_ssl'} ) = Cpanel::IP::Parse::parse( delete $ref{'ssl_ip_port'} );
        ( $ref{'ipv6'}, $ref{'ipv6_is_dedicated'} )      = split( ',', delete $ref{'ipv6_dedicated'} );
        $ref{'ipv6_is_dedicated'} ||= 0;
        $ref{'modsecurity_enabled'} = delete $ref{'modsecurity_disabled'} ? 0 : 1;
        push @controlled_domains, \%ref;
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'domains' => \@controlled_domains };
}

=head2 getdomainowner

=head3 Purpose

Returns the user that owns the domain.

=head3 Arguments

'domain': The domain to lookup

=head3 Output

Returns a hashref with a single 'user' key in the following
format:

        {
            'user' => 'bob'
            .....
        }

If the domain is not owned by a user that the API caller controls,
this function will return undef for the C<user>.

=cut

sub getdomainowner {
    my ( $args, $metadata ) = @_;

    my $operator = $ENV{'REMOTE_USER'} || die Cpanel::Exception->create_raw('Need $ENV{REMOTE_USER}!');

    my $domain = Whostmgr::API::1::Utils::get_required_argument( $args, 'domain' );

    require Cpanel::Domain::Owner;
    my $user = Cpanel::Domain::Owner::get_owner_or_undef($domain);

    if ( length $user ) {
        require Cpanel::AccessControl;
        Cpanel::AccessControl::user_has_access_to_account( $operator, $user ) or $user = undef;
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'user' => $user };
}

=head2 get_current_users_count

=head3 Purpose

Returns the count of current users on the system

=head3 Arguments

None

=head3 Output

Returns a hashref with a single 'users' key in the following
format:

        {
            'users' => 100
        }

=cut

sub get_current_users_count {
    my ( $args, $metadata ) = @_;
    require Cpanel::Config::LoadUserDomains::Count;
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { users => Cpanel::Config::LoadUserDomains::Count::counttrueuserdomains() };
}

=head2 get_maximum_users

Get the maximum users the system's license supports

=over 2

=item Output

=over 3

=item C<HASHREF>

Returns a hashref containing the maximum_users.
This will return the count if there is a limit, or zero if it us unlimited

{
    maximum_users => 0
}

=back

=back

=cut

sub get_maximum_users {
    my ( $args, $metadata ) = @_;

    require Cpanel::Server::Type;
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'maximum_users' => Cpanel::Server::Type::get_max_users() };
}

=head2 get_upgrade_opportunities

=head3 Purpose

Gather information on accounts that may be nearing (or past) resource
usage thresholds that would make them good candidates for upgrading
to a different package.

=head3 Arguments

'nearness_fraction': (Optional) The fraction of 1 at which to consider
usage "near". Defaults to 0.8.

'disk_threshold_blocks': (Optional) A fixed number of blocks to use as
an alternative disk usage threshold.

=head3 Output

Returns a hashref. See OpenAPI documentation on WHM API 1
C<get_upgrade_opportunities> for full detail.

=cut

sub get_upgrade_opportunities {
    my ( $args, $metadata ) = @_;

    require Whostmgr::Accounts::UpgradeOpportunities;
    my ( $uo, $supp ) = Whostmgr::Accounts::UpgradeOpportunities::get(
        nearness_fraction     => $args->{nearness_fraction},        # undef ok
        disk_threshold_blocks => $args->{disk_threshold_blocks},    # undef ok
    );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { upgrade_opportunities => $uo, supplemental => $supp };
}

=head2 get_homedir_roots()

See L<https://go.cpanel.net/get_homedir_roots>.

=cut

sub get_homedir_roots ( $args, $metadata, @ ) {
    require Cpanel::Filesys::Home;

    my @dirs    = Cpanel::Filesys::Home::get_all_homedirs();
    my @payload = map { { path => $_ } } @dirs;

    $metadata->set_ok();

    return { payload => \@payload };
}

#----------------------------------------------------------------------

sub _proxy_this_api_call ( $args, @other_args ) {

    # This works because every API call that calls this function
    # accepts a “user” argument.
    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );

    require Whostmgr::API::1::Utils::Proxy;
    my $remote = Whostmgr::API::1::Utils::Proxy::proxy_if_configured(
        perl_arguments => [ $args, @other_args ],
        worker_type    => 'Mail',
        account_name   => $username,
    );

    return $remote;
}

1;
