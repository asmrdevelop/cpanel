package Whostmgr::API::1::FeatureLists;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;

use Cpanel::Features        ();
use Whostmgr::ACLS          ();
use Cpanel::Encoder::Tiny   ();
use Cpanel::Logger          ();
use Whostmgr::API::1::Utils ();
use Cpanel::Exception       ();
use Cpanel::Features::Load  ();

use Cpanel::LinkedNode::Worker::WHM ();

use constant NEEDS_ROLE => {
    create_featurelist          => undef,
    delete_featurelist          => undef,
    get_available_featurelists  => undef,
    get_feature_metadata        => undef,
    get_feature_names           => undef,
    get_featurelist_data        => undef,
    get_featurelists            => undef,
    get_users_features_settings => undef,
    read_featurelist            => undef,
    update_featurelist          => undef,
};

my $logger;

use Try::Tiny;

=head1 NAME

Whostmgr::API::1::FeatureLists - CRUD functions for managing featurelists

=head1 SYNOPSIS

    use Whostmgr::API::1::FeatureLists ();

    my $list_of_features_available_on_the_server_hr = Whostmgr::API::1::FeatureLists::get_feature_names(undef, {});
    my $featurelists_available_for_user_bob = Whostmgr::API::1::FeatureLists::get_available_featurelists( {}, {} );
    # creates a featurelist with all features disabled
    my $create_new_featurelist_for_bob = Whostmgr::API::1::FeatureLists::create_featurelist( {'featurelist' => 'bob_testing' }, {} );
    # reads the featurelist
    my $read_featurelist_bob_testing = Whostmgr::API::1::FeatureLists::read_featurelist ( {'featurelist' => 'bob_testing' }, {} );
    # updates the featurelist and enabled webmail feature
    my $update_featurelist_bob_testing = Whostmgr::API::1::FeatureLists::update_featurelist( {'featurelist' => 'bob_testing', 'webmail' => 1 }, {} );
    # deletes the featurelist
    my $delete_featurelist_bob_testing = Whostmgr::API::1::FeatureLists::delete_featurelist( {'featurelist' => 'bob_testing' }, {} );

=head1 Methods

=over

=item B<get_feature_name>

Returns an array of hashes that map the "feature id" to the "feature name",

B<Input>:

None

B<Output>:

A hashref containing the list of features available on the server:

    {
        'feature' => [
            ...
            {
                'id' => 'sslmanager',
                'name' => 'SSL Manager',
            },
            {
                'id' => 'theme-switch',
                'name' => 'Theme Switching',
            },
            ...
        ],
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub get_feature_names {
    my ( undef, $metadata ) = @_;
    my $attributes_for_feature = Cpanel::Features::get_features_with_attributes();
    my @feature_list;

    while ( my ( $id, $atts ) = each %$attributes_for_feature ) {
        my %feature = (
            'id' => $id,
            %$atts,
        );
        push @feature_list, \%feature;
    }

    if ( scalar @feature_list ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        return { 'feature' => \@feature_list };
    }

    $metadata->{'result'} = 0;
    $metadata->{'reason'} = 'Unable to retrieve feature list.';
    return;
}

=item B<get_feature_metadata>

Returns an array of hashes that map the "feature id" to the "feature name",

B<Input>:

None

B<Output>:

A hashref containing the list of features available on the server:

    {
        'features' => [
            {
                'id'=> 'addoncgi',
                'name' => 'Site Software'
            },
            {
                'id'=> 'addondomains',
                'name' => 'Addon Domain Manager'
            },
            {
                'id'=> 'advguest',
                'name' => 'Advanced Guestbook'
            }
        ],
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub get_feature_metadata {
    my ( undef, $metadata ) = @_;
    my $attributes_for_feature = Cpanel::Features::load_all_feature_metadata();

    if ( scalar @$attributes_for_feature ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        return { 'features' => $attributes_for_feature };
    }

    $metadata->{'result'} = 0;
    $metadata->{'reason'} = 'Unable to retrieve feature list.';
    return;
}

=item B<get_available_featurelists>

Returns an array containing the names of the featurelists available.

B<Output>:

    {
        'available_featurelists' => [
            'default',
            'disabled',
            'bob_blah'
        ],
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub get_available_featurelists {
    my ( $args, $metadata ) = @_;

    $logger ||= Cpanel::Logger->new();

    # Deprecation is because this API assumes that lack of available
    # feature lists constitutes an error, which, for non-admin resellers
    # isn’t true.
    $logger->deprecated("FeatureLists::get_available_featurelists is deprecated. Please use FeatureLists::get_featurelists.");

    _add_to_args($args);

    my @list_of_available_featurelists = Cpanel::Features::get_user_feature_lists( $args->{'user'}, $args->{'has_root'} );
    foreach my $list (@list_of_available_featurelists) {
        $list = Cpanel::Encoder::Tiny::safe_html_decode_str($list);
    }

    if ( scalar @list_of_available_featurelists ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        return { 'available_featurelists' => \@list_of_available_featurelists };
    }

    $metadata->{'result'} = 0;
    $metadata->{'reason'} = 'Unable to retrieve list of available featurelists';
    return;
}

=item B<get_featurelists>

Returns an array containing the names of the featurelists.

B<Output>:

    {
        'featurelists' => [
            'default',
            'disabled',
            'bob_blah'
        ],
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub get_featurelists {
    my ( $args, $metadata ) = @_;

    _add_to_args($args);

    my @featurelists = Cpanel::Features::get_user_feature_lists( $args->{'user'}, $args->{'has_root'} );
    foreach my $list (@featurelists) {
        $list = Cpanel::Encoder::Tiny::safe_html_decode_str($list);
    }

    # An admin should always have feature lists like “default”.
    # Other resellers, though, can legitimately have no feature lists.

    if ( scalar @featurelists || !$args->{'has_root'} ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        return { 'featurelists' => \@featurelists };
    }

    $metadata->{'result'} = 0;
    $metadata->{'reason'} = 'Unable to retrieve list of available featurelists';
    return;
}

=item B<create_featurelist>

Creates a featurelist with the name, and features specified.

B<Input>:

The following are required to complete this call:

    $args->{featurelist} => 'testing' # creates a featurelist by the name of 'testing'

You can explicitly list which features you want to enable and disable by doing:

    $args->{$feature_id_enable}   => 1  # eg: to enable webmail feature: $args->{'webmail'} = 1
    $args->{$feature_id_disable}  => 0  # eg: to disable webmail feature: $args->{'webmail'} = 0

I<Note>: if a feature is not specified, then it will be disabled.

If a featurelist by the name specified already exists, then this call will return undef, and set the appropriate C<$metadata> details. If you specify:

    $args->{'overwrite'} => 1

Then the featurelist will be overwritten if it exists.

B<Output>:

    {
        'featurelist' => name of featurelist saved,
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub create_featurelist {
    my ( $args, $metadata ) = @_;

    my %args_copy = %$args;

    _add_to_args($args);

    if ( not $args->{'featurelist'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'No featurelist name specified.';
        return;
    }

    my $featurelist = Cpanel::Encoder::Tiny::safe_html_encode_str( delete $args->{'featurelist'} || '' );
    my $has_root    = delete $args->{'has_root'};
    my $user        = delete $args->{'user'};
    my $overwrite   = delete $args->{'overwrite'};

    # Verify reseller's feature list file name format
    if ( !$has_root && $featurelist !~ m/^\Q$user\E_[\w]+/ ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Invalid featurelist name provided: \"$featurelist\" is invalid for reseller \"$user\".";
        return;
    }
    if ( !$overwrite && Cpanel::Features::Load::is_feature_list($featurelist) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Featurelist by that name already exists: \"$featurelist\"";
        return;
    }

    try {
        _propagate_to_worker_nodes(
            local => [
                sub { Cpanel::Features::save_featurelist( $featurelist, $args, $has_root, 1 ) },
                sub { Cpanel::Features::delete_featurelist( $featurelist, $user, $has_root ) },
            ],
            remote => [
                [ create_featurelist => \%args_copy ],
                [ delete_featurelist => { %args_copy{'featurelist'} } ],
            ],
        );

        $metadata->set_ok();
    }
    catch {
        my $trimmed_result = Cpanel::Exception::get_string_no_id($_);
        $metadata->set_not_ok($trimmed_result);
    };

    return if not $metadata->{'result'};

    return { 'featurelist' => $featurelist };
}

=item B<read_featurelist>

Reads the featurelist with the specified name, and returns a hash that maps the "feature ids" to a value indicating whether it is enabled or not.

B<Input>:

The following are required to complete this call:

    $args->{featurelist} => 'testing' # reads the featurelist by the name of 'testing'

B<Output>:

    {
        'featurelist' => name of featurelist read,
        'features' => {
            ...
            'changemx' => 1,
            'webmail' => 0,
            ...
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub read_featurelist {
    my ( $args, $metadata ) = @_;

    $logger ||= Cpanel::Logger->new();
    $logger->deprecated("FeatureLists::read_featurelist is deprecated. Please use FeatureLists::get_featurelist_data.");

    _add_to_args($args);

    my $featurelist = Cpanel::Encoder::Tiny::safe_html_encode_str( delete $args->{'featurelist'} || '' );
    my $has_root    = delete $args->{'has_root'};
    my $user        = delete $args->{'user'};
    if ( not $featurelist ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'No featurelist name specified.';
        return;
    }

    if ( not Cpanel::Features::is_featurelist_accessible( $featurelist, $has_root, $user ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Unable to access featurelist specified: \"$featurelist\"";
        return;
    }

    my $features = {};
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    try {
        $features = Cpanel::Features::Load::load_featurelist($featurelist);
        if ( !ref $features || !keys %$features ) {
            die "Specified featurelist does not exist: \"$featurelist\"\n";
        }
    }
    catch {
        chomp $_;
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $_;
    };

    return if not $metadata->{'result'};
    return { 'featurelist' => $featurelist, 'features' => $features };
}

=item B<get_featurelist_data>

Reads the featurelist with the specified name, and returns a hash that maps the "feature ids" to a value indicating whether it is enabled or not.

B<Input>:

The following are required to complete this call:

    $args->{featurelist} => 'testing' # reads the featurelist by the name of 'testing'

B<Output>:

    {
        'featurelist' => name of featurelist read,
        'features' => {
            'changemx' => { 'disabled'=>0, addon=>0, 'value'=>1},
            'webmail' => { 'disabled'=>1, addon=>0, 'value'=>0},
            ...
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub get_featurelist_data {
    my ( $args, $metadata ) = @_;

    _add_to_args($args);

    my $featurelist = Cpanel::Encoder::Tiny::safe_html_encode_str( delete $args->{'featurelist'} || '' );
    my $has_root    = delete $args->{'has_root'};
    my $user        = delete $args->{'user'};
    if ( not $featurelist ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'No featurelist name specified.';
        return;
    }

    if ( not Cpanel::Features::is_featurelist_accessible( $featurelist, $has_root, $user ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Unable to access featurelist specified: \"$featurelist\"";
        return;
    }

    my $features;
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    try {
        $features = Cpanel::Features::get_featurelist_information($featurelist);
        if ( not scalar keys @{$features} ) {
            die "Specified featurelist does not exist: \"$featurelist\"\n";
        }
    }
    catch {
        chomp $_;
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $_;
    };

    return if not $metadata->{'result'};
    return { 'featurelist' => $featurelist, 'features' => $features };
}

=item B<update_featurelist>

Updates featurelist with the name, and features specified.

B<Input>:

The following are required to complete this call:

    $args->{featurelist} => 'testing' # creates a featurelist by the name of 'testing'

You will want to include features you want to enable and disable by doing:

    $args->{$feature_id_enable}   => 1  # eg: to enable webmail feature: $args->{'webmail'} = 1
    $args->{$feature_id_disable}  => 0  # eg: to disable webmail feature: $args->{'webmail'} = 0

I<Note>: If a featurelist by the name specified does NOT exist, then this call will create the list and set the features specified.

B<Output>:

    {
        'featurelist' => name of featurelist read,
        'updated_features' => {
            ...
            'changemx' => 1,
            'webmail' => 0,
            ...
        },
        'invalid_features' => [
            ...
            feature ids that are not valid
            ...
        ],
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub update_featurelist {
    my ( $args, $metadata ) = @_;

    my %args_copy = %$args;

    my $non_html_featurelist = $args->{'featurelist'};

    _add_to_args($args);

    my $html_featurelist = Cpanel::Encoder::Tiny::safe_html_encode_str( delete $args->{'featurelist'} || '' );

    my $has_root = delete $args->{'has_root'};
    my $user     = delete $args->{'user'};
    if ( not $html_featurelist ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'No featurelist name specified.';
        return;
    }

    if ( not Cpanel::Features::is_featurelist_accessible( $html_featurelist, $has_root, $user ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Unable to access featurelist specified: \"$html_featurelist\"";
        return;
    }

    my $status_quo_hr = Cpanel::Features::Load::load_featurelist($html_featurelist);

    my ( $updated_features, $invalid_features );

    try {
        _propagate_to_worker_nodes(
            local => [
                sub {
                    ( $updated_features, $invalid_features ) = Cpanel::Features::update_featurelist( $html_featurelist, $args, $user, $has_root );
                    if ( not $updated_features ) {
                        $updated_features = {};
                    }
                },
                sub {
                    if ($status_quo_hr) {
                        () = Cpanel::Features::update_featurelist( $html_featurelist, $status_quo_hr, $user, $has_root );
                    }
                },
            ],
            remote => [
                [ update_featurelist => \%args_copy ],
                !$status_quo_hr ? () : [
                    update_featurelist => {
                        featurelist => $non_html_featurelist,
                        %$status_quo_hr,
                    }
                ],
            ],
        );

        $metadata->set_ok();
    }
    catch {
        my $trimmed_result = Cpanel::Exception::get_string_no_id($_);
        $metadata->set_not_ok($trimmed_result);
    };

    return if not $metadata->{'result'};

    return {
        'featurelist'      => $html_featurelist,
        'updated_features' => $updated_features,
        'invalid_features' => $invalid_features,
    };
}

=item B<delete_featurelist>

Deletes the featurelist with the specified name.

B<Input>:

The following are required to complete this call:

    $args->{featurelist} => 'testing' # deletes the featurelist by the name of 'testing'

B<Output>:

    {
        'deleted_featurelist' => 'testing',
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub delete_featurelist {
    my ( $args, $metadata ) = @_;

    my %args_copy = %$args;

    _add_to_args($args);

    my $featurelist = Cpanel::Encoder::Tiny::safe_html_encode_str( delete $args->{'featurelist'} || '' );
    my $has_root    = delete $args->{'has_root'};
    my $user        = delete $args->{'user'};
    if ( not $featurelist ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'No featurelist name specified.';
        return;
    }

    if ( not Cpanel::Features::is_featurelist_accessible( $featurelist, $has_root, $user ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Unable to access featurelist specified: \"$featurelist\"";
        return;
    }

    try {
        _propagate_to_worker_nodes(
            local => [
                sub {
                    Cpanel::Features::delete_featurelist( $featurelist, $user, $has_root );
                },
            ],
            remote => [
                [ delete_featurelist => \%args_copy ],
            ],
        );

        $metadata->set_ok();
    }
    catch {
        chomp $_;

        $metadata->set_not_ok($_);
    };

    return if not $metadata->{'result'};
    return { 'deleted_featurelist' => $featurelist };
}

=item B<get_users_features_settings>

Gets an xref list for users and and features and their override vs featurelist setting.

B<Input>:

The following args can be used in this call:

    $args->{user-*} => user(s) to include in the list. At least one is required.
    $args->{feature-*} => optional, feature(s) to include in the list, if none are specified, all are returned

B<Output>:

    {
        'user_features_settings' => [
            {
                user:"banner",
                feature:"telepathy",
                feature_list: "default",
                feature_list_setting:"0",
                cpuser_setting:"1"
            },
        ]
    }

=cut

sub get_users_features_settings {
    my ( $args, $metadata ) = @_;

    my @users = Whostmgr::API::1::Utils::get_length_required_arguments( $args, 'user' );
    if ( !@users ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] );
    }
    my @features = Whostmgr::API::1::Utils::get_arguments( $args, 'feature' );
    my @feature_settings;

    my @warnings;

    foreach my $user (@users) {

        my $user_features = Cpanel::Features::get_user_feature_settings( $user, \@features, ignore_invalid_features => 1, warnings => \@warnings );

        foreach my $feature ( @{$user_features} ) {
            push @feature_settings, {
                'user'                 => $user,
                'feature'              => $feature->{'feature'},
                'feature_list'         => $feature->{'feature_list'},
                'feature_list_setting' => $feature->{'feature_list_setting'},
                'cpuser_setting'       => $feature->{'cpuser_setting'},
            };
        }
    }

    if (@warnings) {

        # only warnings when part of the features are valid
        my %uniq = map { $_->to_locale_string_no_id => undef } @warnings;
        $metadata->{'output'}->{'warnings'} = [ sort keys %uniq ];

        # API throws an error when requestion only unknown features
        die $warnings[0] unless @feature_settings;
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'users_features_settings' => \@feature_settings };

}

sub _add_to_args {
    my ($args) = @_;
    $args->{'has_root'} = Whostmgr::ACLS::hasroot();
    $args->{'user'}     = $ENV{'REMOTE_USER'};

    return;
}

=back

=cut

#----------------------------------------------------------------------

sub _propagate_to_worker_nodes (%opts) {
    my %propagate_args;

    my $local_ar = $opts{'local'};
    @propagate_args{ 'local_action', 'local_undo' } = @$local_ar;

    my %node_api_obj;
    my $get_api_obj_cr = sub ($node_obj) {
        return $node_api_obj{ $node_obj->hostname() } ||= Cpanel::LinkedNode::Worker::WHM::create_node_api_obj($node_obj);
    };

    my $remote_ar = $opts{'remote'};

    my ( $remote_action_fn, $remote_action_args ) = @{ $remote_ar->[0] };
    my $remote_undo = $remote_ar->[1];

    $propagate_args{'remote_action'} = sub ($node_obj) {
        my $api_obj = $get_api_obj_cr->($node_obj);

        local $@;
        eval { $api_obj->request_whmapi1_or_die( $remote_action_fn, $remote_action_args ) } or do {

            # If an undo method was given, then propagate this error to
            # trigger that undo. If no undo was given, assume we don’t want
            # to roll back changes, and just warn.
            $remote_undo ? die : warn;
        };
    };

    if ($remote_undo) {
        my ( $remote_undo_fn, $remote_undo_args ) = @$remote_undo;

        $propagate_args{'remote_undo'} = sub ($node_obj) {
            my $api_obj = $get_api_obj_cr->($node_obj);

            $api_obj->request_whmapi1_or_die( $remote_undo_fn, $remote_undo_args );
        };
    }

    Cpanel::LinkedNode::Worker::WHM::do_on_all_nodes(%propagate_args);

    return;
}

1;
