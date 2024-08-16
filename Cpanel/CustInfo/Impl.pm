package Cpanel::CustInfo::Impl;

# cpanel - Cpanel/CustInfo/Impl.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic(RequireUseWarnings) -- needs auditing before adding

=head1 NAME

Cpanel::CustInfo::Impl - Implements the core operations for Cpanel::CustInfo

=head1 SYNOPSIS

    use Cpanel::CustInfo::Impl;

    my $contact_info = Cpanel::CustInfo::Impl::fetch_addresses(
        appname    => $Cpanel::appname,
        cpuser     => $Cpanel::user,
        cphomedir  => $Cpanel::homedir,
        username   => $Cpanel::authuser,
    );

=head1 DESCRIPTION

This module implements the core operations for the public interfaces in
Cpanel::CustInfo and semi-private interfaces in Cpanel::CustInfo::Save.
The module has very limited dependence on global variables unlike the
original implementation it replaces.

=cut

# Avoid using in Cpanel.pm since this
# is used in WHM and Cpanel.pm will
# already be used in when in cpanel
# context.
use Cpanel::ContactInfo::Notify ();
use Cpanel::CustInfo::Model     ();
use Cpanel::CustInfo::Util      ();
use Cpanel::CustInfo::Validate  ();
use Cpanel::Encoder::Tiny       ();
use Cpanel::Exception           ();
use Cpanel::Fcntl               ();
use Cpanel::FileUtils::Open     ();
use Cpanel::IP::Remote          ();
use Cpanel::LoadModule          ();
use Cpanel::StringFunc::Trim    ();

=head1 METHODS

=head2 fetch_display(appname => $appname, cphomedir => $cphomedir, cpuser => $cpuser, username => $username)

Fetch all the customer info properties that are usable.

=over 3

=item C<< appname >> [in, required]

A string representing the name of the current application: cpanel or webmail.

=item C<< cphomedir >> [in, required]

A string representing the cpanel user's home directory.

=item C<< cpuser >> [in, required]

A string representing the cpanel user name.

=item C<< username >> [in, required]

A string representing the name of the user we are saving. This may be a webmail
account belonging to the cpanel user or the cpanel user themselves.

=back

B<Returns>: On success, returns an arrayref of hashes with the following
properties:

=over 3

=item C<< type >> [out]

A string representing the type of property: string or boolean.

=item C<< value >> [out]

A string or boolean representing the raw value of the property.

=item C<< enabled >> [out]

A 1 or 0.

=item C<< name >> [out]

A string representing the name of the property.

=item C<< descp >> [out]

A string representing the description of the property.

=item C<< onchangeparent >> [out, optional]

A string that points to another boolean notice property.

=back

=cut

sub fetch_display {
    my (%ARGS) = @_;

    my $is_webmail = Cpanel::CustInfo::Util::is_user_virtual( $ARGS{appname}, $ARGS{cpuser}, $ARGS{username} );

    Cpanel::CustInfo::Validate::validate_account_or_die( $ARGS{username}, $is_webmail, $ARGS{cpuser} );

    my $dir = Cpanel::CustInfo::Util::get_dot_cpanel( $ARGS{cphomedir}, $is_webmail, $ARGS{username} );
    return if !length $dir;

    require Cpanel::DataStore;
    my $data = Cpanel::DataStore::fetch_ref( $dir . '/contactinfo' );

    if ( ref $data ne 'HASH' ) { $data = {}; }

    my @RSD;
    my $contact_fields = Cpanel::CustInfo::Model::get_contact_fields($is_webmail);
    my ( $team_user_info, $cpuser_obj );

    if ( $ENV{'TEAM_USER'} && !$is_webmail ) {
        require Cpanel::Team::Config;
        my $team_obj = Cpanel::Team::Config->new( $ENV{'TEAM_OWNER'} );
        $team_user_info = $team_obj->get_team_user( $ENV{'TEAM_USER'} );
    }
    else {
        $cpuser_obj = !$is_webmail && !$ENV{'TEAM_USER'} && do {
            require Cpanel::Config::LoadCpUserFile;
            Cpanel::Config::LoadCpUserFile::load_or_die( $ARGS{'username'} );
        };
    }

    foreach my $field_name (@Cpanel::CustInfo::Model::FIELD_SORT) {
        next if !$contact_fields->{$field_name};

        my $template = $contact_fields->{$field_name};
        my $value    = $data->{$field_name};

        if ( $ENV{'TEAM_USER'} && !$is_webmail ) {
            if ( $field_name eq 'email' ) {
                $value = $team_user_info->{'contact_email'};
            }
            elsif ( $field_name eq 'second_email' ) {
                $value = $team_user_info->{'secondary_contact_email'};
            }
        }
        elsif ( !$is_webmail ) {
            if ( $field_name eq 'email' ) {
                $value = $cpuser_obj->contact_emails_ar()->[0];
            }
            elsif ( $field_name eq 'second_email' ) {
                $value = $cpuser_obj->contact_emails_ar()->[1];
            }
        }
        elsif ( $field_name eq 'email' && !length($value) ) {
            $value = $ARGS{username};
        }

        if ( $template->{'type'} eq 'boolean' ) {
            push @RSD, _format_boolean_field( $field_name, $template, $value );
        }
        else {
            push @RSD, _format_string_field( $field_name, $template, $value );
        }
    }

    return \@RSD;
}

=head2 fetch_addresses(appname => $appname, cphomedir => $cphomedir, cpuser => $cpuser, username => $username, no_default => $no_default)

Fetch all the address-related customer information properties, including
contact email addresses and pushbullet access token.

=over 3

=item C<< appname >> [in, required]

A string representing the name of the current application: cpanel or webmail.

=item C<< cphomedir >> [in, required]

A string representing the cpanel user's home directory.

=item C<< cpuser >> [in, required]

A string representing the cpanel user name.

=item C<< username >> [in, required]

A string representing the name of the user we are saving. This may be a webmail
account belonging to the cpanel user or the cpanel user themselves.

=item C<< no_default >> [in, required]

A boolean. Only relevant for WebMail users. If falsy and the user lacks a
primary contact email address, the username is given as the primary.

=back

B<Returns>: On success, returns an arrayref of hashes with the following
properties:

=over 3

=item C<< type >> [out]

A string representing the type of property: string or boolean.

=item C<< value >> [out]

A string or boolean representing the raw value of the property.

=item C<< enabled >> [out]

A 1 or 0.

=item C<< name >> [out]

A string representing the name of the property.

=item C<< descp >> [out]

A string representing the description of the property.

=back

=cut

sub fetch_addresses {
    my (%ARGS) = @_;

    my $is_webmail = Cpanel::CustInfo::Util::is_user_virtual( $ARGS{appname}, $ARGS{cpuser}, $ARGS{username} );
    Cpanel::CustInfo::Validate::validate_account_or_die( $ARGS{username}, $is_webmail, $ARGS{cpuser} );

    my $dir = Cpanel::CustInfo::Util::get_dot_cpanel( $ARGS{cphomedir}, $is_webmail, $ARGS{username} );

    if ( !length $dir ) {
        die Cpanel::Exception::create(
            'UserdataLookupFailure',
            'The system cannot find the .cpanel directory for “[_1]”.',
            [ $ARGS{username} ],
        );
    }

    my $contact_fields = Cpanel::CustInfo::Model::get_contact_fields($is_webmail);

    require Cpanel::DataStore;
    my $data = Cpanel::DataStore::fetch_ref( $dir . '/contactinfo' );
    if ( ref $data ne 'HASH' ) { $data = {}; }

    my ( $team_user_info, $cpuser_obj );
    if ( $ENV{'TEAM_USER'} && !$is_webmail ) {
        require Cpanel::Team::Config;
        my $team_obj = Cpanel::Team::Config->new( $ENV{'TEAM_OWNER'} );
        $team_user_info = $team_obj->get_team_user( $ENV{'TEAM_USER'} );
    }
    else {
        $cpuser_obj = !$is_webmail && !$ENV{'TEAM_USER'} && do {
            require Cpanel::Config::LoadCpUserFile;
            Cpanel::Config::LoadCpUserFile::load_or_die( $ARGS{'username'} );
        };
    }

    my @RSD;
    foreach my $field_name (@Cpanel::CustInfo::Model::FIELD_SORT) {
        next if !$contact_fields->{$field_name};
        next if $contact_fields->{$field_name}{'type'} ne 'string';    # Only string properties

        my $value = $data->{$field_name};

        if ( $ENV{'TEAM_USER'} && !$is_webmail ) {
            if ( $field_name eq 'email' ) {
                $value = $team_user_info->{'contact_email'};
            }
            elsif ( $field_name eq 'second_email' ) {
                $value = $team_user_info->{'secondary_contact_email'};
            }
        }
        elsif ( !$is_webmail ) {
            if ( $field_name eq 'email' ) {
                $value = $cpuser_obj->contact_emails_ar()->[0];
            }
            elsif ( $field_name eq 'second_email' ) {
                $value = $cpuser_obj->contact_emails_ar()->[1];
            }
        }
        elsif ( $field_name eq 'email' && !length($value) ) {
            $value = $ARGS{'username'} if !$ARGS{no_default};
        }

        my $template = $contact_fields->{$field_name};
        push @RSD, _format_string_field( $field_name, $template, $value, 1 );
    }

    return \@RSD;
}

=head2 fetch_preferences(appname => $appname, cphomedir => $cphomedir, cpuser => $cpuser, username => $username)

Fetch all the usable boolean customer information properties. These are used
primarily to enable/disable the sending of notices.

=over 3

=item C<< appname >> [in, required]

A string representing the name of the current application: cpanel or webmail.

=item C<< cphomedir >> [in, required]

A string representing the cpanel user's home directory.

=item C<< cpuser >> [in, required]

A string representing the cpanel user name.

=item C<< username >> [in, required]

A string representing the name of the user we are saving. This may be a webmail
account belonging to the cpanel user or the cpanel user themselves.

=back

B<Returns>: On success, returns an arrayref of hashes with the following
properties:

=over 3

=item C<< type >> [out]

A string representing the type of property: string or boolean.

=item C<< value >> [out]

A string or boolean representing the raw value of the property.

=item C<< enabled >> [out]

A 1 or 0.

=item C<< name >> [out]

A string representing the name of the property.

=item C<< descp >> [out]

A string representing the description of the property.

=item C<< onchangeparent >> [out, optional]

A string that points to another boolean notice property.

=back

=cut

sub fetch_preferences {
    my (%ARGS) = @_;

    my $is_webmail = Cpanel::CustInfo::Util::is_user_virtual( $ARGS{appname}, $ARGS{cpuser}, $ARGS{username} );

    Cpanel::CustInfo::Validate::validate_account_or_die( $ARGS{username}, $is_webmail, $ARGS{cpuser} );

    my $dir = Cpanel::CustInfo::Util::get_dot_cpanel( $ARGS{cphomedir}, $is_webmail, $ARGS{username} );
    return if !length $dir;

    require Cpanel::DataStore;
    my $data = Cpanel::DataStore::fetch_ref( $dir . '/contactinfo' );
    if ( ref $data ne 'HASH' ) { $data = {}; }

    my $contact_fields = Cpanel::CustInfo::Model::get_contact_fields($is_webmail);
    my @RSD;

    foreach my $field_name (@Cpanel::CustInfo::Model::FIELD_SORT) {
        next if !$contact_fields->{$field_name};
        next if $contact_fields->{$field_name}{'type'} eq 'string';    # Only boolean properties
        my $features_ar = $contact_fields->{$field_name}{'features'};
        next if $features_ar && !_has_any_feature($features_ar);

        my $template = $contact_fields->{$field_name};
        my $value    = $data->{$field_name};
        push @RSD, _format_boolean_field( $field_name, $template, $value );
    }

    return \@RSD;
}

=head2 save(appname => $appname, cphomedir => $cphomedir, cpuser => $cpuser, username => $username, data => \%args)

Save customer information to the system.

=over 3

=item C<< appname >> [in, required]

A string representing the name of the current application: cpanel or webmail.

=item C<< cphomedir >> [in, required]

A string representing the cpanel user's home directory.

=item C<< cpuser >> [in, required]

A string representing the cpanel user name.

=item C<< username >> [in, required]

A string representing the name of the user we are saving. This may be a webmail
account belonging to the cpanel user or the cpanel user themselves.

=item C<< data >> [in, required]

A hashref containing the properties to save to the customer information files.

=back

B<Returns>: On success, returns an arrayref of hashes with the following
properties:

=over 3

=item C<< name >> [out]

A string representing the key from C<%CONTACT_FIELDS>.

=item C<< descp >> [out]

A string representing the localized description of the field_name.

=item C<< value >> [out]

A string or boolean representing the raw value of the property.

=item C<< display_value >> [out]

A string that is the same as value, but with whitespace trimmed. Will be
C<on> or C<off> for boolean fields.

=back

=cut

sub save {
    my (%ARGS) = @_;

    return if !_has_any_feature( [Cpanel::CustInfo::Model::FEATURES_TO_EDIT_STRINGS] );

    my $is_webmail = Cpanel::CustInfo::Util::is_user_virtual( $ARGS{appname}, $ARGS{cpuser}, $ARGS{username} );

    Cpanel::CustInfo::Validate::validate_account_or_die( $ARGS{username}, $is_webmail, $ARGS{cpuser} );

    my $dir = Cpanel::CustInfo::Util::get_dir( $ARGS{cphomedir}, $is_webmail, $ARGS{username} );

    # Adjust the arguments
    my $DATA = delete $ARGS{data};
    $ARGS{dir} = $dir;

    if ( !length $dir ) {
        die Cpanel::Exception::create(
            'UserdataLookupFailure',
            'The system cannot find the home directory for cPanel user “[_1]”.',
            [ $ARGS{username} ],
        );
    }
    my $rsd_ref        = _savecontactinfo( \%ARGS, $DATA );
    my $contact_fields = Cpanel::CustInfo::Model::get_contact_fields($is_webmail);

    my @display_results;
    foreach my $field ( @{$rsd_ref} ) {
        my $features_ar = $contact_fields->{ $field->{'name'} }{'features'};
        next if $features_ar && !_has_any_feature($features_ar);
        next if !defined $contact_fields->{ $field->{'name'} };
        $field->{'descp'} = $contact_fields->{ $field->{'name'} }{'descp'}->to_string();
        push @display_results, $field;
    }

    # Switched back to load_perl_module so bin/depend will not
    # push this into updatenow.static
    Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin');
    if ($is_webmail) {
        Cpanel::AdminBin::adminrun( 'reseller', 'SYNCMAILUSER', $ARGS{username} );
    }
    elsif ( $ENV{'TEAM_USER'} ) {

        # Team user does not have cpuser and does not require Cpanel::ContactInfo::Sync.
        return \@display_results;
    }
    else {
        Cpanel::AdminBin::adminrun( 'reseller', 'UPDATECONTACTINFO', 0 );
    }

    return \@display_results;
}

=head2 _savecontactinfo(\%OPTS, \%DATA)

Semi-private call to save customer contact information. Used in many internal
modules where the path to save to is already calculated.

=over 3

=item C<< OPTS >> [in, required]

A hashref contains the options for the user to save.

=over 3

=item C<< appname >> [in, required]

A string representing the name of the current application: cpanel or webmail.

=item C<< cphomedir >> [in, required]

A string representing the cpanel user's home directory.

=item C<< cpuser >> [in, required]

A string representing the cpanel user name.

=item C<< username >> [in, required]

A string representing the name of the user we are saving. This may be a webmail
account belonging to the cpanel user or the cpanel user themselves.

=back

=item C<< DATA >> [in, required]

A hashref containing the data to save.

B<NOTE:> By default, any undefined options will be set to an empty list.
The keys should match those from C<%Cpanel::CustInfo::Modle::CONTACT_FIELDS>.

=back

B<Returns>: On success, returns an arrayref of hashes with the following
properties:

=over 3

=item C<< name >> [out]

A string representing the key from C<%CONTACT_FIELDS>.

=item C<< descp >> [out]

A string representing the localized description of the field_name.

=item C<< value >> [out]

A string or boolean representing the saved value for the property.

=item C<< display_value >> [out]

A string that is the same as value, but with whitespace trimmed. Will be
C<on> or C<off> for boolean fields.

=back

=cut

sub _savecontactinfo {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $OPTS, $DATA ) = @_;
    Cpanel::CustInfo::Validate::validate_not_demo_mode_or_die();
    Cpanel::CustInfo::Model::get_all_possible_contact_fields();    # TODO: Would be nice to remove the need for this sideeffect method (LC-4069)

    my $appname  = $OPTS->{appname}  || $Cpanel::appname || $Cpanel::App::appname;    # PPI NO PARSE - only used if loaded
    my $cpuser   = $OPTS->{cpuser}   || $Cpanel::user;                                # PPI NO PARSE - only used if loaded
    my $username = $OPTS->{username} || $Cpanel::authuser || $Cpanel::user;           # PPI NO PARSE - only used if loaded

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'appname' ] )  if !$appname;
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'cpuser' ] )   if !$cpuser;
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'username' ] ) if !$username;

    my $dir = $OPTS->{dir};

    my $is_webmail = Cpanel::CustInfo::Util::is_user_virtual( $appname, $cpuser, $username );

    my @RSD;
    my $cf = {};

    my $dotcpaneldir = Cpanel::CustInfo::Util::ensure_dot_cpanel($dir);
    my $cinfo_file   = "$dotcpaneldir/contactinfo";

    if ( -e $cinfo_file ) {

        # Open the customer info file.
        require Cpanel::DataStore;
        $cf = Cpanel::DataStore::fetch_ref($cinfo_file);    # NOTE: Hides errors
        if ( ref $cf ne 'HASH' ) {
            $cf = {};
        }
    }
    else {
        # Create the customer info file.
        Cpanel::FileUtils::Open::sysopen_with_real_perms( my $s_fh, $cinfo_file, Cpanel::Fcntl::or_flags(qw(O_NOFOLLOW O_TRUNC O_CREAT)), 0640 ) or do {
            die Cpanel::Exception::create(
                'IO::FileCreateError',
                [
                    path        => $cinfo_file,
                    error       => $!,
                    permissions => 0640,
                ]
            );
        };
    }

    my $notification_prefs = Cpanel::ContactInfo::Notify::get_notification_preference_from_contact_data($cf);
    my $notifications_hr   = {};

    my $contact_fields = Cpanel::CustInfo::Model::get_contact_fields($is_webmail);

    my ( $cpuser_email_changed, $team_user_info, $cpuser_obj );

    if ( $ENV{'TEAM_USER'} && !$is_webmail ) {
        require Cpanel::Team::Config;
        my $team_obj = Cpanel::Team::Config->new( $ENV{'TEAM_OWNER'} );
        $team_user_info = $team_obj->get_team_user( $ENV{'TEAM_USER'} );
    }
    else {
        $cpuser_obj = !$is_webmail && !$ENV{'TEAM_USER'} && do {
            require Cpanel::Config::LoadCpUserFile;
            Cpanel::Config::LoadCpUserFile::load_or_die( $OPTS->{cpuser} );
        };
    }

    foreach my $field (@Cpanel::CustInfo::Model::FIELD_SORT) {
        next if !exists $contact_fields->{$field};

        # Clean the field if its NULL
        if ( length $DATA->{$field} && $DATA->{$field} eq 'NULL' ) {
            $DATA->{$field} = q<>;
        }

        my ( $display_value, $current_value, $new_value );

        # Save the current value for the report
        $current_value = $cf->{$field};

        if ( !defined $cf->{$field} ) {
            $cf->{$field} = $contact_fields->{$field}{'default'};
        }

        my $features_ar  = $contact_fields->{$field}{'features'};
        my $has_features = defined $DATA->{$field} && _has_any_feature($features_ar);

        if ( $contact_fields->{$field}->{'type'} eq 'boolean' ) {
            if ($has_features) {
                $cf->{$field} = $DATA->{$field} ? 1 : 0;
            }
            $display_value = $cf->{$field} ? 'on' : 'off';
        }
        else {
            if ($has_features) {
                my $trimmed_value = Cpanel::StringFunc::Trim::ws_trim( $DATA->{$field} );
                $trimmed_value = Cpanel::Encoder::Tiny::safe_html_decode_str($trimmed_value);

                if ( $trimmed_value eq q{} || $contact_fields->{$field}->{'validator'}->($trimmed_value) ) {
                    $cf->{$field} = $trimmed_value;

                    # need to check this for email_account
                    if ( $ENV{'TEAM_USER'} && !$is_webmail && grep { $field eq $_ } Cpanel::CustInfo::Model::EMAIL_FIELDS ) {
                        my $email_key = $field eq "second_email" ? 'secondary_contact_email' : 'contact_email';
                        my $old_value = $team_user_info->{$email_key};
                        $cpuser_email_changed ||= $old_value ne $trimmed_value;
                    }
                    elsif ( !$is_webmail && grep { $field eq $_ } Cpanel::CustInfo::Model::EMAIL_FIELDS ) {
                        my $cpuser_key = $contact_fields->{$field}{'cpuser_key'};
                        my $old_value  = $cpuser_obj->{$cpuser_key} // q<>;
                        $cpuser_email_changed ||= $old_value ne $trimmed_value;
                    }

                }
                else {
                    $cf->{$field} = Cpanel::Encoder::Tiny::safe_html_decode_str( $cf->{$field} );
                }
            }

            $display_value = Cpanel::StringFunc::Trim::ws_trim( $cf->{$field} );
        }

        $new_value = $cf->{$field};

        push @RSD,
          {
            'name'          => $field,
            'display_value' => $display_value,
            'value'         => $cf->{$field},
          };

        my $notification_delta_hr = Cpanel::ContactInfo::Notify::get_notification_delta(
            'key_notification_preference' => $notification_prefs->{$field},
            'new_value'                   => $new_value,
            'current_value'               => $current_value,
        );

        $notifications_hr->{$field} = $notification_delta_hr if $notification_delta_hr;
    }

    $cf->{'ip'}     = Cpanel::IP::Remote::get_current_remote_ip();
    $cf->{'origin'} = 'cpanel';

    # Notifications for contactinfo changes for cPanel users are sent in Cpanel::ContactInfo::Sync
    if ( $is_webmail && keys %$notifications_hr ) {
        Cpanel::AdminBin::adminstor(
            'reseller',
            'NOTIFYMAILUSERCONTACTCHANGE',
            {
                'user'             => $username,
                'origin'           => $cf->{'origin'},
                'ip'               => $cf->{'ip'},
                'notifications_hr' => $notifications_hr,
            }
        );
    }

    # Notifications for contactinfo changes for team users are sent directly here.
    if ( $ENV{'TEAM_USER'} && keys %$notifications_hr && !$is_webmail ) {
        $notifications_hr->{'cpuser_emails'} = [ $team_user_info->{'contact_email'}, $team_user_info->{'secondary_contact_email'} ];
        my %notification_args = (
            'username'         => "$ENV{'TEAM_USER'}\@$ENV{'TEAM_LOGIN_DOMAIN'}",
            'to_user'          => "$ENV{'TEAM_USER'}\@$ENV{'TEAM_LOGIN_DOMAIN'}",
            'origin'           => 'cpanel',
            'ip'               => Cpanel::IP::Remote::get_current_remote_ip(),
            'notifications_hr' => $notifications_hr
        );
        Cpanel::AdminBin::Call::call( 'Cpanel', 'teamconfig', 'SEND_CONTACT_INFO_CHANGE_NOTIFICATIONS', %notification_args );
    }

    # We don’t sync contact emails from the homedir to the cpuser
    # datastore anymore; instead we write them directly.
    if ( !$is_webmail && $cpuser_email_changed ) {
        die Cpanel::Exception->create_raw('Contact email address updates now require authentication. If you called API 2’s legacy CustInfo::savecontactinfo, switch to UAPI’s ContactInformation::* calls.');
    }

    # NOTE: This is not race-safe; however, it hopefully isn’t much of a
    # problem since users probably don’t change their contact settings
    # very often.
    require Cpanel::DataStore;
    Cpanel::DataStore::store_ref( $cinfo_file, $cf );

    return \@RSD;
}

sub _has_any_feature {
    my ($features_ar) = @_;

    my $feature_cr = main->can('hasfeature');

    # Avoid tickling the IncludeDiscrepancies monster:
    $feature_cr //= Cpanel->can('hasfeature');    ## PPI NO PARSE

    return 0 unless $feature_cr;

    foreach my $feature ( @{$features_ar} ) {
        return 1 if $feature_cr->($feature);
    }
    return 0;
}

sub _format_string_field {
    my ( $field_name, $template, $value, $encode ) = @_;
    $value ||= $template->{'default'};
    if ($encode) {
        $value = Cpanel::Encoder::Tiny::safe_html_encode_str($value);
    }
    return {
        'enabled' => 1,
        'type'    => $template->{'type'},
        'value'   => $value,
        'name'    => $field_name,
        'descp'   => $template->{'descp'}->to_string(),
    };
}

sub _format_boolean_field {
    my ( $field_name, $template, $value ) = @_;

    return {
        'type'           => $template->{'type'},
        'value'          => 1,
        'enabled'        => ( ( defined $value && $value ne '' ) ? int $value : $template->{'default'} ),
        'name'           => $field_name,
        'descp'          => $template->{'descp'}->to_string(),
        'onchangeparent' => length $template->{'onchangeparent'} ? $template->{'onchangeparent'}        : '',
        'infotext'       => $template->{'infotext'}              ? $template->{'infotext'}->to_string() : '',
    };
}

1;
