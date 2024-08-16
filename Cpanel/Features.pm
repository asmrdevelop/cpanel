package Cpanel::Features;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;

use Cpanel::LoadModule             ();
use Cpanel::LoadFile               ();
use Cpanel::Exception              ();
use Cpanel::Features::Load         ();
use Cpanel::Debug                  ();
use Cpanel::Reseller               ();
use Cpanel::Validate::Username     ();
use Cpanel::Features::Cpanel       ();
use Cpanel::cPAddons::Class        ();
use Cpanel::StringFunc::Case       ();
use Cpanel::Features::Lists        ();
use Cpanel::Config::CpUserGuard    ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Server::Type           ();

our ( $VERSION, $feature_desc_dir, $feature_list_dir );

BEGIN {
    *VERSION          = *Cpanel::Features::Lists::VERSION;
    *feature_desc_dir = *Cpanel::Features::Lists::feature_desc_dir;
    *feature_list_dir = *Cpanel::Features::Lists::feature_list_dir;
}

*featurelist_file = *Cpanel::Features::Load::featurelist_file;
*load_featurelist = *Cpanel::Features::Load::load_featurelist;
*is_feature_list  = *Cpanel::Features::Load::is_feature_list;

# plug tiny functions
*_ensure_featurelist_dir           = *Cpanel::Features::Lists::ensure_featurelist_dir;
*get_feature_lists                 = *Cpanel::Features::Lists::get_feature_lists;
*get_user_feature_lists            = *Cpanel::Features::Lists::get_user_feature_lists;
*get_user_and_global_feature_lists = *Cpanel::Features::Lists::get_user_and_global_feature_lists;

my $optional_components;

sub is_global_featurelist ($file) {

    return $file !~ m/_/;
}

sub is_featurelist_accessible ( $file, $has_root, $user ) {

    return $has_root || $file =~ m/^${user}_/;
}

sub is_addon_list ($list) {
    return $list =~ m/\.cpaddons$/;
}

sub verify_feature_entry ( $feature_name, $list ) {

    return if !$feature_name;
    return if !$list;
    return if ( $list =~ m/^\.\.?$/ );
    return if !-e featurelist_file($list);
    return if !is_feature_list($list);

    my $path_name = featurelist_file($list);

    open( my $fh, '<', $path_name ) or Cpanel::Debug::log_die("Error: Unable to open file \"$path_name\".\n");
    my @feature_list = <$fh>;
    close $fh or Cpanel::Debug::log_die("Error: Unable to close file \"$path_name\".\n");

    my @entry_list = grep ( /^$feature_name=/, @feature_list );

    return wantarray ? @entry_list : scalar(@entry_list);
}

sub add_override_features_for_user ( $user = undef, $features_hr = undef ) {    # for now prefer the MissingParameter exception to the signature one

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] )        if !length $user;
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'features_hr' ] ) if !$features_hr || !keys %$features_hr;
    Cpanel::Validate::Username::user_exists_or_die($user);

    my %feature_lookup = map { $_ => 1 } ( Cpanel::Features::load_feature_names(), Cpanel::Features::load_addon_feature_names() );

    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
    for my $key ( keys %$features_hr ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The value “[_1]” is not a valid feature name.', [$key] ) if !defined $feature_lookup{$key};
        my $feature_key = _make_feature_key($key);
        $cpuser_guard->{'data'}{$feature_key} = $features_hr->{$key} ? '1' : '0';
    }
    $cpuser_guard->save();

    return;
}

sub remove_override_features_for_user ( $user = undef, $features_ar = undef ) {    # for now prefer the MissingParameter exception to the signature one

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] )        if !length $user;
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'features_ar' ] ) if !$features_ar || !@$features_ar;
    Cpanel::Validate::Username::user_exists_or_die($user);

    my %feature_lookup = map { $_ => 1 } ( Cpanel::Features::load_feature_names(), Cpanel::Features::load_addon_feature_names() );

    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
    for my $key (@$features_ar) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The value “[_1]” is not a valid feature name.', [$key] ) if !defined $feature_lookup{$key};
        my $feature_key = _make_feature_key($key);
        delete $cpuser_guard->{'data'}{$feature_key} if exists $cpuser_guard->{'data'}{$feature_key};
    }
    $cpuser_guard->save();

    return;
}

sub add_feature_config ( $featurelist, $feature, $val ) {

    _ensure_featurelist_dir();
    Cpanel::Debug::log_die("No featurelist specified.\n") unless defined $featurelist and length $featurelist;
    Cpanel::Debug::log_die("No feature specified.\n")     unless defined $feature     and length $feature;
    $val = $val ? '1' : '0';

    # Make sure feature entry does not exist before adding it.
    if ( -e featurelist_file($featurelist) ) {
        my @feature_entry_result = verify_feature_entry( $feature, $featurelist );
        if ( scalar(@feature_entry_result) ) {
            Cpanel::Debug::log_die("Feature name \"$feature\" already exists in feature list \"$featurelist\": \n@feature_entry_result \n");
        }
    }

    open( my $fh, '>>', featurelist_file($featurelist) )
      or Cpanel::Debug::log_die("Unable to update '$featurelist': $!");
    print {$fh} $feature, '=', $val, "\n";
    close $fh;
    return;
}

sub modify_feature (%args) {

    return if !$args{feature};
    $args{value} = $args{value} ? 1 : 0;

    my @lists;
    if ( $args{list} && is_feature_list( $args{list} ) ) {
        @lists = ( $args{list} );
    }
    elsif ( !$args{list} ) {
        @lists = grep { !/^(?:disabled|default|Mail Only)$/ } get_feature_lists();
    }
    else {
        print "$args{list} is not a known feature list.\n" if $args{verbose};
        return;
    }

    foreach my $file (@lists) {
        my $remove_entry = ( $file eq 'disabled' ) && $args{value} || $args{'delete'};
        if ( open my $ft_fh, '+<', featurelist_file($file) ) {
            my @features;
            my $has_feature = 0;
            while ( my $line = readline $ft_fh ) {
                if ( $line =~ m/^\Q$args{feature}\E=/ ) {
                    next if $has_feature;
                    $has_feature = 1;
                    my $add_type = $args{value} ? 'Enabling' : 'Disabling';
                    print "$add_type $args{feature} in feature list $file\n" if $args{verbose};
                    next                                                     if $remove_entry;
                    $line = "$args{feature}=$args{value}\n";
                }
                push @features, $line;
            }
            if ( !$has_feature && !$remove_entry ) {
                my $add_type = $args{value} ? 'enabling' : 'disabling';
                print "Adding and $add_type $args{feature} in feature list $file\n" if $args{verbose};
                push @features, "$args{feature}=$args{value}\n";
            }
            seek( $ft_fh, 0, 0 );
            print {$ft_fh} join( '', @features );
            truncate( $ft_fh, tell($ft_fh) );
            close $ft_fh;
        }
    }
    return;
}

sub get_default_mail_only_features() {
    my @mail_only_features = (
        'autoresponders',
        'blockers',
        'boxtrapper',
        'changemx',
        'csvimport',
        'defaultaddress',
        'emailarchive',
        'emailauth',
        'emaildomainfwd',
        'emailtrace',
        'forwarders',
        'getstart',
        'lists',
        'password',
        'popaccts',
        'setlang',
        'spamassassin',
        'spambox',
        'style',
        'updatecontact',
        'updatenotificationprefs',
        'videotut',
        'webmail',
        'traceaddy',    # Deprecated value, but still valid - especially as we use this value during the 'feature list migration'
    );

    return @mail_only_features;
}

sub get_featurelist_information ($featurelist_name) {

    my @aggregated_featurelist_info = ();

    my %valid_feature_names     = ();
    my %disabled_list_info      = ();
    my %addon_feature_list_info = ();

    my $is_cpaddon_featurelist = is_addon_list($featurelist_name);

    unless ( -f featurelist_file($featurelist_name) ) {
        return \@aggregated_featurelist_info;
    }

    my %feature_list_info = load_featurelist( $featurelist_name, '=' );

    my %addon_feature_names = map { $_ => 1 } ( Cpanel::cPAddons::Class->new( 'featurelist' => $featurelist_name )->load_cpaddon_feature_names() );

    # loads disabled cpaddons featurelist
    my %addon_disabled_list_info = ();

    if ( $featurelist_name ne 'disabled.cpaddons' ) {
        %addon_disabled_list_info = load_featurelist( 'disabled.cpaddons', '=' );
    }

    if ( !$is_cpaddon_featurelist ) {

        # gets all feature names including cpaddons
        %valid_feature_names = map { $_ => 1 } ( load_all_feature_names() );

        my $addon_feature_list_name = $featurelist_name . ".cpaddons";

        my $addon_features_file = featurelist_file($addon_feature_list_name);
        if ( -f $addon_features_file ) {
            %addon_feature_list_info = load_featurelist( $addon_feature_list_name, '=' );
        }
        else {
            %addon_feature_list_info = map { $_ => '1' } keys %addon_feature_names;
        }

        %feature_list_info = ( %feature_list_info, %addon_feature_list_info );

        if ( $featurelist_name ne 'disabled' ) {
            %disabled_list_info = load_featurelist( 'disabled', '=' );
            %disabled_list_info = ( %disabled_list_info, %addon_disabled_list_info );
        }
    }
    else {
        %valid_feature_names     = %addon_feature_names;
        %addon_feature_list_info = %feature_list_info;
        %disabled_list_info      = %addon_disabled_list_info;
    }

    foreach my $feature ( keys %valid_feature_names ) {
        push @aggregated_featurelist_info,
          {
            'id'          => "$feature",
            'is_disabled' => ( $featurelist_name ne 'disabled.cpaddons' && $featurelist_name ne 'disabled' ) && exists $disabled_list_info{$feature} ? "1"                          : "0",
            'value'       => exists $feature_list_info{$feature}                                                                                     ? $feature_list_info{$feature} : "1"
          };
    }

    return \@aggregated_featurelist_info;

}

sub delete_featurelist ( $featurelist_name, $user, $has_root = undef ) {

    if ( is_featurelist_accessible( $featurelist_name, $has_root, $user ) ) {
        _clear_feature_cache($featurelist_name);

        my $feature_file = featurelist_file($featurelist_name);
        unlink $feature_file or die "Failed to delete featurelist \"$featurelist_name\": $!\n";
        unlink "$feature_file.cpaddons";
    }
    else {
        die "Unable to access featurelist specified: \"$featurelist_name\"\n";
    }

    return;
}

sub update_featurelist ( $featurelist_name, $features_hr, $user, $has_root = undef ) {    ## no critic qw(ProhibitManyArgs)

    my %current_features = load_featurelist( $featurelist_name, '=' );
    my %valid_feature_names;

    if ( is_addon_list($featurelist_name) ) {
        %valid_feature_names = map { $_ => 1 } Cpanel::cPAddons::Class->new( 'featurelist' => $featurelist_name )->load_cpaddon_feature_names();
    }
    else {
        %valid_feature_names = map { $_ => 1 } ( load_feature_names(), load_addon_feature_names() );
    }

    my ( $modified_features, @invalid_features );
    foreach my $feature ( keys %{$features_hr} ) {
        if ( $valid_feature_names{$feature} ) {
            unless ( exists $current_features{$feature} && $current_features{$feature} eq $features_hr->{$feature} ) {
                $modified_features->{$feature} = $features_hr->{$feature};
                $current_features{$feature} = $features_hr->{$feature};
            }
        }
        else {
            push @invalid_features, $feature;
        }
    }

    if ( defined $modified_features ) {
        save_featurelist( $featurelist_name, \%current_features, $has_root );
    }

    return ( $modified_features, \@invalid_features );
}

sub save_featurelist ( $name, $features_hr, $has_root = undef, $populate = undef ) {    ## no critic qw(ProhibitManyArgs)

    my $file = featurelist_file($name);

    my $user = $ENV{'REMOTE_USER'};

    if ( Cpanel::Reseller::isreseller($user) ) {

        # Verify reseller's feature list file name format
        if ( !$has_root && $name !~ m/\Q$user\E_[\w]+/ ) {
            Cpanel::Debug::log_info("Unable to save feature list: its filename \"$name\" is invalid for reseller \"$user\".\n");
            return;
        }
    }
    else {
        Cpanel::Debug::log_info("User \"$user\" is not a reseller and does not have access to save the feature list \"$name\"\n");
        return;
    }

    # In fixing FB#86553, we discovered that feature list files were being written in html encoded format.
    # Handling the html encoded files properly will take a bit of work and will be done in a future release
    #my ( $valid_feature_list_name, $message ) = Cpanel::Validate::FeatureList::is_valid_feature_list_name($name);
    #die $message if !$valid_feature_list_name;

    my $is_normal_list = $name ne 'default' && $name ne 'disabled';
    my ( @new_list, @new_list_cpaddons );

    my @cpaddon_feature_names = Cpanel::cPAddons::Class->new( 'featurelist' => $name )->load_cpaddon_feature_names();
    if ( is_addon_list($name) ) {
        foreach my $featurename (@cpaddon_feature_names) {
            next unless defined $features_hr->{$featurename} || $populate;
            if ( ( $features_hr->{$featurename} || '' ) ne '1' ) {
                push @new_list, "$featurename=0";
            }
        }
    }
    else {
        foreach my $featurename ( load_feature_names(), load_addon_feature_names() ) {
            next unless defined $features_hr->{$featurename} || $populate;
            if ( ( $features_hr->{$featurename} || '' ) ne '1' ) {
                push @new_list, "$featurename=0";
            }
            elsif ($is_normal_list) {
                push @new_list, "$featurename=1";
            }
        }
        foreach my $featurename (@cpaddon_feature_names) {
            next unless defined $features_hr->{$featurename} || $populate;
            if ( ( $features_hr->{$featurename} || '' ) ne '1' ) {
                push @new_list_cpaddons, "$featurename=0";
            }
        }

        _propagate_component_features( $features_hr, $name, \@new_list );
    }

    open( my $fh, '>', $file ) or die "Unable to open '$file': $!\n";
    print {$fh} map { "$_\n" } sort @new_list;
    close($fh);

    # CPANEL-10577: Let's also be nice to our users and create a cpaddons list if we *need* one.
    if ( !is_addon_list($name) && scalar(@new_list_cpaddons) ) {
        open( my $fh, '>', "$file.cpaddons" ) or die "Unable to open '$file': $!\n";
        print {$fh} map { "$_\n" } sort @new_list_cpaddons;
        close($fh);
    }

    _clear_feature_cache($name);

    return 1;
}

sub _clear_feature_cache ($feature_name) {

    my ($feature_cache_file) = Cpanel::Features::Cpanel::calculate_cache_file_name_and_maxmtime( Cpanel::Features::Cpanel::fetch_feature_file_list_from_featurelist($feature_name) );
    unlink($feature_cache_file);

    Cpanel::Features::Cpanel::clear_memory_cache();

    return;
}

sub _propagate_component_features ( $features_hr, $featurelist_name, $list ) {

    $list ||= [];

    # Allows old values to persist, despite the component being "disabled"
    #  or "unlicensed". Add default
    #
    # NOTE: other mechanisms specific to a given component will be
    #  responsible for enforcing the disabled/unlicensed state.
    my $previously_stored_features = Cpanel::Features::Load::load_featurelist( $featurelist_name, '=' );

    Cpanel::LoadModule::load_perl_module('Cpanel::Component');
    $optional_components ||= Cpanel::Component->init();
    my $available_component_features = $optional_components->get_component_features();

    foreach my $componentfeature ( load_component_feature_descs(1) ) {
        my $feature_value;
        if ( ref $previously_stored_features && exists $previously_stored_features->{ $componentfeature->[0] } ) {

            # has previous value, only update value if they are currently
            #  allowed to use component, otherwise just retain previous value
            if ( exists $available_component_features->{ $componentfeature->[0] } ) {
                $feature_value = ( $features_hr->{ $componentfeature->[0] } ) ? '1' : '0';
                push @{$list}, $componentfeature->[0] . '=' . $feature_value;
            }
            else {
                push @{$list}, $componentfeature->[0] . '=' . $previously_stored_features->{ $componentfeature->[0] };
            }
        }
        elsif ( exists $available_component_features->{ $componentfeature->[0] } ) {

            # new feature since last list update; component is active, so
            #  write on/off as requested
            $feature_value = ( $features_hr->{ $componentfeature->[0] } ) ? '1' : '0';
            push @{$list}, $componentfeature->[0] . '=' . $feature_value;
        }
        ## else do nothing; the feature is "on" by default (convention with
        ##  features); other component mechanisms will verify if that is valid
    }
    return;
}

sub load_feature_descs() {
    my @feature_desc;
    _load_feature_descs_file( "$feature_desc_dir/features", \@feature_desc );

    _filter_features( \@feature_desc );

    return @feature_desc;
}

sub get_features_with_attributes() {
    my @feature_desc = ( load_feature_descs(), load_addon_feature_descs(), load_component_feature_descs() );
    my %attributes_for_feature;

    foreach my $aref (@feature_desc) {
        my ( $name, $desc ) = @$aref;
        $attributes_for_feature{$name} = {
            'name' => $desc,
        };
    }

    return wantarray ? %attributes_for_feature : \%attributes_for_feature;
}

sub load_feature_names() {
    my @feature_names;

    _load_feature_descs_names( "$feature_desc_dir/features", \@feature_names );
    _filter_features( \@feature_names );

    return @feature_names;
}

sub _get_filepaths_arrayref ($dir) {
    return [] unless -d $dir;

    opendir( my $dh, $dir ) or die "Unable to read '$dir': $!\n";
    my @files = map { index( $_, '.' ) == 0 ? () : "$dir/$_" } readdir($dh);
    closedir($dh);

    return \@files;
}

sub _filter_features ($list) {
    return if ref $list ne 'ARRAY';

    # For now we only filter 'addoncgi' key and 'team_manager' for non-team-enabled users
    my $is_simple_list = !ref $list->[0];

    for ( my $i = $#$list; $i >= 0; --$i ) {
        my $id = $is_simple_list ? $list->[$i] : $list->[$i]->[0];

        if ( ( $id eq 'addoncgi' && -e '/var/cpanel/cpaddons.disabled' ) || ( $id eq 'team_manager' && !Cpanel::Server::Type::has_feature('teams') ) ) {
            splice @$list, $i, 1;    #strip from the list
        }
    }

    return 1;
}

sub load_addon_feature_descs() {
    my @feature_desc;
    foreach my $subdir ( 'addonsfeatures', 'addonfeatures' ) {
        my $dir = "$feature_desc_dir/$subdir";

        foreach my $file ( @{ _get_filepaths_arrayref($dir) } ) {
            _load_feature_descs_file( $file, \@feature_desc );
        }
    }

    return @feature_desc;
}

sub load_addon_feature_names() {
    my @feature_names;
    foreach my $subdir ( 'addonsfeatures', 'addonfeatures' ) {
        my $dir = "$feature_desc_dir/$subdir";

        foreach my $file ( @{ _get_filepaths_arrayref($dir) } ) {
            _load_feature_descs_names( $file, \@feature_names );
        }
    }

    return @feature_names;
}

sub load_component_feature_descs ( $load_all_possible = 0 ) {
    my @feature_desc;

    Cpanel::LoadModule::load_perl_module('Cpanel::Component');
    $optional_components ||= Cpanel::Component->init();
    my $component_based_features = $optional_components->get_feature_details_keyby_component($load_all_possible) || {};
    foreach my $array_ref_of_features ( values %{$component_based_features} ) {
        foreach my $feature ( @{$array_ref_of_features} ) {
            push @feature_desc, [ $feature->{'name'}, $feature->{'description'}, $feature->{'default_value'}, $feature->{'is_addon'}, $feature->{'is_plugin'} ];
        }
    }

    return @feature_desc;
}

sub load_component_feature_names() {

    Cpanel::LoadModule::load_perl_module('Cpanel::Component');
    $optional_components ||= Cpanel::Component->init();
    my $component_based_features = $optional_components->get_component_features() || {};

    return keys %{$component_based_features};
}

sub get_user_feature_settings ( $user, $features_ar, %opts ) {

    my $cpuser_data       = Cpanel::Config::LoadCpUserFile::load($user);
    my $feature_list_name = $cpuser_data->{'FEATURELIST'} || 'default';
    my @all_features      = Cpanel::Features::load_all_feature_names();
    my %all_feature_keys  = map { $_ => '1' } @all_features;

    my $feature_list = {};
    Cpanel::Features::Cpanel::augment_hashref_with_features( $feature_list_name, $feature_list );

    if ( scalar @{$features_ar} == 0 ) {
        @$features_ar = @all_features;
    }

    my @requested_features;

    foreach my $feature ( @{$features_ar} ) {
        if ( !$all_feature_keys{$feature} ) {
            my $exception = Cpanel::Exception::create( "InvalidParameter", 'The value “[_1]” is not a valid feature name.', [$feature] );

            if ( $opts{ignore_invalid_features} ) {
                push $opts{warnings}->@*, $exception if ref $opts{warnings};
                next;
            }

            die $exception;
        }
        my $feature_key   = _make_feature_key($feature);
        my $feature_value = '1';
        if ( defined $feature_list->{$feature_key} && $feature_list->{$feature_key} eq '0' ) {
            $feature_value = '0';
        }
        push @requested_features, {
            'feature'              => $feature,
            'feature_list'         => $feature_list_name,
            'feature_list_setting' => $feature_value,
            'cpuser_setting'       => $cpuser_data->{$feature_key},
        };
    }

    return \@requested_features;

}

#
# Given a feature file name $file, load the feature names into the array
# referenced by $names_ar.
sub _load_feature_descs_names ( $file, $names_ar ) {
    push @{$names_ar}, map { index( $_, '#' ) > -1 && /^\s*#/ ? () : ( split( /:/, $_, 2 ) )[0] } split( m{\n}, Cpanel::LoadFile::load($file) );
    return;
}

#
# Given a feature file name $file, load the feature descriptions into the array
# referenced by $desc_ar. Each description is represented by an anonymous array
# of [ 'name' => 'description' ].
sub _load_feature_descs_file ( $file, $desc_ar ) {
    push @{$desc_ar}, map { chomp(); index( $_, '#' ) > -1 && /^\s*#/ ? () : [ split( /:/, $_, 2 ) ] } split( m{\n}, Cpanel::LoadFile::load($file) );    ## no critic qw(ControlStructures::ProhibitMutatingListFunctions)
    return;
}

sub load_all_feature_names() {

    my @feature_names = ( load_feature_names(), load_addon_feature_names(), load_component_feature_names(), Cpanel::cPAddons::Class->new()->load_cpaddon_feature_names() );

    return @feature_names;
}

sub load_all_feature_metadata() {

    my @feature_desc = ();

    my @featurelist_descs = ( load_feature_descs(), load_component_feature_descs() );

    foreach my $aref (@featurelist_descs) {
        my ( $key, $human_friendly_name, $default, $is_addon, $is_plugin ) = @$aref;
        push @feature_desc, {
            'id'         => "$key",
            'name'       => "$human_friendly_name",
            'is_cpaddon' => $is_addon  ? "1" : "0",
            'is_plugin'  => $is_plugin ? "1" : "0",
        };
    }

    my @plugin_feature_desc = load_addon_feature_descs();
    foreach my $aref (@plugin_feature_desc) {
        my ( $key, $human_friendly_name ) = @$aref;
        push @feature_desc, { 'id' => "$key", 'name' => "$human_friendly_name", 'is_cpaddon' => "0", 'is_plugin' => "1" };
    }

    my @cpaddon_feature_desc = Cpanel::cPAddons::Class->new()->load_cpaddon_feature_descs();

    foreach my $aref (@cpaddon_feature_desc) {
        my ( $key, $human_friendly_name ) = @$aref;
        push @feature_desc, { 'id' => "$key", 'name' => "$human_friendly_name", 'is_cpaddon' => "1", 'is_plugin' => "0" };
    }

    return \@feature_desc;
}

sub _make_feature_key ($feature) {

    return 'FEATURE-' . Cpanel::StringFunc::Case::ToUpper($feature);
}

1;    # Magic true value required at end of module
__END__

=head1 NAME

Cpanel::Features - encapsulate access to the features and feature lists

=head1 VERSION

This document describes Cpanel::Features version 0.0.4


=head1 SYNOPSIS

    use Cpanel::Features;

    if ( !is_featurelist_accessible( 'fred_features', $is_root, $user ) ) {
        print "You don't have access to 'fred_features'\n";
        return;
    }

    foreach my $f ( load_feature_descs() ) {
        my ($name, $desc) = @($f};
        print "'$desc': tag='$name'\n";
    }


=head1 DESCRIPTION

The features in the WHM/Cpanel interface are controlled through a set of
files located in the F<whostmgr> directory under the installation directory.

As this information is needed in multiple places, this module hides the actual
implementation in terms of the files and directories involved. This allows
other code to depend on the interface without scattering file reading code
(and the hardcoded paths) throughout the codebase.

=head1 INTERFACE

The interface for this module can be partitioned into two groups: access to
the feature lists and access to features.

=head2 FEATURE LISTS

=head3 Cpanel::Features::featurelist_file( $name )

Returns the full pathname to the feature list named C<$name>. This method
breaks encapsulation with the rest of the module, but it allows for simpler
conversion of code from the old approach to the new one.

=head3 Cpanel::Features::is_global_featurelist( $name )

Returns true if the featurelist named C<$name> is a global featurelist. In
other words, a featurelist that is not associated with a particular reseller.

=head3 Cpanel::Features::is_featurelist_accessible( $name, $is_root, $user )

Returns true if the featurelist named C<$name> is accessible by C<$user>,
either because the list is associated with C<$user> or because C<$is_root>
is true.

=head3 Cpanel::Features::is_feature_list( $name )

Returns true if the name C<$name> refers to a featurelist.

=head3 Cpanel::Features::verify_feature_entry( $feature_name, $list)

Returns the entry count of feature name (C<$feature_name>) if it exists
in the feature list (C<$list>) when calling in a scalar context,
or returns its corresponding entries when calling in a list context.

=head3 Cpanel::Features::add_feature_config( $featurelist, $feature, $value )

Adds a new feature (C<$feature>) entry to the end of the (C<$featurelist>)
featurelist.  Should only be used when creating the feature for the first time.
The supported named parameters are as listed below. (To change a feature,
use C<modify_feature> instead.)

=over 4

=item feature

This required parameter names the feature to add.

=item value

This required parameter specifies the boolean value to which we want to set
the feature.

=item list

This required parameter names a single feature list to which the feature entry is
added.

=item verbose

This optional boolean parameter specifies whether or not the method prints
to the current output as it runs.

=back

=head3 Cpanel::Features::modify_feature( %args )

Uses the named arguments to modify one or more feature lists on disk. Only
existing features are changed. The supported named parameters are:

=over 4

=item feature

This required parameter names the feature to modify.

=item value

This required parameter specifies the boolean value to which we want to set
the feature.

=item list

This optional parameter names a single feature list to which the change is
applied.

=item verbose

This optional boolean parameter specifies whether or not the method prints
to the current output as it runs.

=back

=head3 Cpanel::Features::get_feature_lists( $is_root )

Returns a list of all of the feature lists on the system. If C<$is_root> is
true, the lists I<default> and I<disabled> are added even if they do not
exist in the system.

=head3 Cpanel::Features::get_user_feature_lists( $user, $is_root )

Returns a list of all of the feature lists on the system. If C<$is_root> is
true, the lists I<default> and I<disabled> are added even if they do not
exist in the system. If C<$is_root> is false, the lists are filtered to only
include those that are associated with the supplied user.

=head3 Cpanel::Features::load_featurelist( $name )

Returns a hash of the features for the feature list named C<$name>. The keys
of the hash are the features and the values are 1 for any enabled feature and
false otherwise.

=head3 Cpanel::Features::save_featurelist( $name, $feature_hr )

Write the feature list named C<$name> described by the hash reference
C<$feature_hr> into the appropriate file.

=head2 FEATURES

=head3 Cpanel::Features::load_feature_descs()

Returns a list of anonymous arrays describing the standard features. The
anonymous arrays are each of the form C<< [ 'name' => 'description' ] >>

=head3 Cpanel::Features::load_feature_names()

Returns a list of standard feature names in the order stored in the feature
file.

=head3 Cpanel::Features::load_addon_feature_descs()

Returns a list of anonymous arrays describing the features from the
F<addonfeatures> and F<addonsfeatures> directories. The anonymous arrays are
each of the form C<< [ 'name' => 'description' ] >>

=head3 Cpanel::Features::load_component_feature_descs()

Returns a list of anonymous arrasys describing the features managed by licensed components
for the server. The arrays are each of the form C<< [ name, description, default_value, is_addon, is_plugin ] >>
where:

=over

=item name - string - Name of the feature.

=item description - string - Description of the feature.

=item default_value - boolean - 1 when enabled by default, 0 when disabled by default.

=item is_addon - boolean - 1 when the component was installed as an addon.

=item is_plugin - boolean - 1 when the component was installed as a modern plugin.

=back

=head3 Cpanel::Features::load_addon_feature_names()

Returns a list of feature names collected from the feature files in the
F<addonfeatures> and F<addonsfeatures> directories.

=head3 Cpanel::Features::load_component_feature_names()

Returns a list of the features managed by licensed components for the server.

=head3 Cpanel::Features::get_user_features_settings( $user, $features )

Returns a list of features and their coordinating settings in the cpuser file
and the featurelist the user is assigned to. If no features are specified, all
features in the feature list are returned.

=head1 DIAGNOSTICS

=over

=item C<< Unable to create feature dir '%s': %s >>

Possibly permission issues with parent directory.

=item C<< Unable to open feature dir '%s': %s >>

Possibly permission issues with the feature directory.

=item C<< Unable to load featurelist '%s': %s >>

Check file permissions.

=item C<< Unable to open '%s': %s >>

Check file permissions.

=item C<< Unable to read '%s': %s >>

Check permissions on the directory specified in the message.

=back
