package Whostmgr::Transfers::ArchiveManager::Validate;

# cpanel - Whostmgr/Transfers/ArchiveManager/Validate.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

# RR Audit: FG

use Try::Tiny;

use Cpanel::Config::CpUser::MigrationData    ();
use Cpanel::CustInfo::Get                    ();
use Cpanel::DB::Utils                        ();
use Cpanel::Dovecot::Config                  ();
use Cpanel::Exception                        ();
use Cpanel::LoadModule                       ();
use Cpanel::Locale                           ();
use Cpanel::SSL::DefaultKey::Constants       ();
use Cpanel::Validate::Domain                 ();
use Cpanel::Validate::EmailRFC               ();
use Cpanel::Validate::FeatureList            ();
use Cpanel::Validate::FilesystemPath         ();
use Cpanel::Validate::PackageName            ();
use Cpanel::Validate::UUID                   ();
use Whostmgr::AccountEnhancements::Constants ();
use Whostmgr::DNS::Constants                 ();
use Whostmgr::Packages::Load                 ();

my $__cpuser_validation_hashref;

our $VALIDATE_SKIPPED = 0;    # Skip the key and produce a warning in the form of a skipped item
our $VALIDATE_OK      = 1;    # Key ok
our $VALIDATE_DISCARD = 2;    # Discard the key without a warning

my %KEYS_NOT_TO_WARN_ON = map { $_ => undef } qw(
  __CACHE_DATA_VERSION
  IP
  DBOWNER
  DOMAINS
  USER
  DOMAIN
  OWNER
  DNS
);

# Get validated cpuser data for account restorations.
#    By the time we need validated cpuser data, the account should already exist on the system.
#    Several of the cpuser keys are left out intentionally because we would rather use what was created during create account.
#    Skipped keys are skipped by restricted restore, do not influence unrestricted restore.
# Parameters:
#    - user here should be the username of the restored user on disk, not the username found in the backup file
#    - cpuser_data should be a hashref of the cpuser data from the backup file
sub validate_cpuser_data {
    my ( $user, $orig_cpuser_data ) = @_;

    die Cpanel::Exception::create_raw( 'InvalidParameter', 'validate_cpuser_data required cpuser_data in hashref format' ) if !UNIVERSAL::isa( $orig_cpuser_data, 'HASH' );

    my $validated_cpuser_data = {};
    my $skipped_cpuser_data   = {};
    my $discarded_cpuser_data = {};

    my $cpuser_data = {%$orig_cpuser_data};

    for my $cpuser_key ( keys %$cpuser_data ) {
        my $cpuser_value = $cpuser_data->{$cpuser_key};
        my ( $validation_key, $domain ) = ( $cpuser_key, undef );

        if ( $validation_key =~ /\Q$Whostmgr::AccountEnhancements::Constants::USERFILE_PREFIX\E/ ) {
            $skipped_cpuser_data->{$cpuser_key} = _locale()->maketext( "Restricted restore does not import third-party user configurations.", $validation_key );
            next;
        }
        elsif ( $validation_key =~ /-/ ) {

            # Some keys also have additional domain information delimited by a '-';
            # check for that and validate the domain.

            ( $validation_key, $domain ) = ( split( '-', $validation_key, 2 ) )[ 0, 1 ];
            if ( !length $domain ) {
                $skipped_cpuser_data->{$cpuser_key} = 'The domain portion of the multi-part key is not set';
                next;
            }
            my ( $status, $reason ) = _validate_domain( $user, $domain );
            if ( $status == $VALIDATE_SKIPPED ) {
                $skipped_cpuser_data->{$cpuser_key} = $reason;
                next;
            }
            elsif ( $status == $VALIDATE_DISCARD ) {
                $discarded_cpuser_data->{$cpuser_key} = $reason;
                next;
            }
        }

        my $value_type = ref $cpuser_value;

        # Some cpuser values are array references.
        if ( !$value_type ) {

            # validate the scalar value
            my ( $status, $reason ) = _validate_value( $user, $validation_key, $cpuser_value );
            if ( $status == $VALIDATE_SKIPPED ) {
                $skipped_cpuser_data->{$cpuser_key} = $reason;
                next;
            }
            elsif ( $status == $VALIDATE_DISCARD ) {
                $discarded_cpuser_data->{$cpuser_key} = $reason;
                next;
            }

            $validated_cpuser_data->{$cpuser_key} = $cpuser_value;
        }
        elsif ( $value_type eq 'ARRAY' ) {

            # Go through the array and only use values that validate properly
            my $status;
            my @validated_values = grep { ( ($status) = _validate_value( $user, $validation_key, $_ ) ) } @$cpuser_value;

            $validated_cpuser_data->{$cpuser_key} = \@validated_values if @validated_values;
        }
        else {
            $skipped_cpuser_data->{$cpuser_key} = _locale()->maketext( 'The key, “[_1]” has an invalid value type of: “[_2]”.', $cpuser_key, $value_type );
        }
    }

    # force USER and DBOWNER as appropriate
    $validated_cpuser_data->{'USER'}    = $user;
    $validated_cpuser_data->{'DBOWNER'} = Cpanel::DB::Utils::username_to_dbowner($user);

    return ( $validated_cpuser_data, $skipped_cpuser_data, $discarded_cpuser_data );
}

sub _validate_value {
    my ( $user, $validation_key, $value ) = @_;

    my $value_validation = _cpuser_validation_hashref()->{$validation_key};

    # if the key, sans any tacked on domains, is not in the validation hash, we don't know about it
    if ( !$value_validation ) {
        my $key_lookup = ( $validation_key =~ /\AX?DNS(:?\d+)?\z/ ) ? 'DNS' : $validation_key;
        if ( exists $KEYS_NOT_TO_WARN_ON{$key_lookup} ) {
            return ( $VALIDATE_DISCARD, _locale()->maketext( "The system will restore the key “[_1]” in another stage.", $validation_key ) );
        }
        else {
            return ( $VALIDATE_SKIPPED, _locale()->maketext( "The key “[_1]” is unknown, so the system will not restore this key.", $validation_key ) );
        }
    }

    my $validation_type = ref $value_validation;

    # a validation can currently be either a code reference or a regex
    if ( $validation_type eq 'CODE' ) {
        my ( $status, $reason ) = $value_validation->( $user, $value );

        if ( !defined $value ) {
            $value = q{};
        }

        return ( $status, "The value for “$validation_key”, “$value”, is invalid: $reason" ) if $status != $VALIDATE_OK;
    }
    elsif ( $validation_type eq 'Regexp' ) {
        return ( $VALIDATE_SKIPPED, "The value '$value' is invalid." ) if $value !~ /$value_validation/;
    }
    else {
        die "Unknown validation type: $validation_type";    #should never happen
    }

    return $VALIDATE_OK;
}

#for testing
sub _get_package_extension_cpuser_keys {
    my ( undef, $extensions_defaults_ref ) = Whostmgr::Packages::Load::get_all_package_extensions();

    return keys %$extensions_defaults_ref;
}

sub _cpuser_validation_hashref {

    # qr{} cannot happen during CHECK or perlcc will die

    if ( !$__cpuser_validation_hashref ) {
        my $mxcheck_re_part = join( '|', map { quotemeta } @Whostmgr::DNS::Constants::MXCHECK_OPTIONS );

        my $boolean_validation_regex    = qr{\A[01]\z};
        my $limit_validation_regex      = qr{\A(?:unlimited|[0-9]+)\z};
        my $alpha_numeric_regex         = qr{\A[0-9a-zA-Z]+\z};
        my $numeric_regex               = qr{\A[0-9]+\z};
        my $item_name_regex             = qr{\A[0-9a-zA-Z-_]+\z};
        my $comma_delimited_value_regex = qr{\A[0-9a-zA-Z-_,]+\z}x;
        my $version_number_regex        = qr{\A[0-9]+(\.[0-9]+){1,3}\z};
        my $license_env_type_regex      = qr{\A[0-9a-zA-Z- ]+\z};

        # copied over from AccountEnhancements::Validate::validate_id_format()
        my $enhancement_id_regex = qr{\A[0-9a-z_-]{1,32}\z};

        # IP is left intentionally out of this listb since during a restore
        # the IP assigned (or already assigned) to the main domain
        # will determine the account IP.
        #
        # Also note that KEY-DOMAIN CpUser keys are validated in parts,
        # where the first part of the key is in this validation function.
        # USER, DBOWNER, DOMAIN, and OWNER are also left intentionally
        # out of this list, as they should have been created during the
        # ACCOUNT creation step.
        #
        $__cpuser_validation_hashref = {

            # Account information
            'STARTDATE'               => $numeric_regex,
            'MTIME'                   => $numeric_regex,
            'SUSPENDTIME'             => $numeric_regex,
            'SUSPENDED'               => $numeric_regex,
            'OUTGOING_MAIL_SUSPENDED' => $numeric_regex,
            'OUTGOING_MAIL_HOLD'      => $numeric_regex,
            'FEATURELIST'             => \&_validate_feature_name,
            'CONTACTEMAIL'            => \&_validate_contactemail,
            'CONTACTEMAIL2'           => \&_validate_contactemail,
            'LOCALE'                  => $item_name_regex,
            'RS'                      => $item_name_regex,
            'LANG'                    => $item_name_regex,
            'PREVIOUS_THEME'          => $item_name_regex,
            'MAILBOX_FORMAT'          => \&_validate_mailbox_format,
            'LEGACY_BACKUP'           => $boolean_validation_regex,
            'BACKUP'                  => $boolean_validation_regex,
            'HOMEDIRLINKS'            => \&_validate_abs_path,
            'SSL_DEFAULT_KEY_TYPE'    => \&_validate_ssl_default_key_type,
            'CHILD_WORKLOADS'         => \&_validate_child_workloads,

            'PLAN'              => \&_validate_package_name,
            _PACKAGE_EXTENSIONS => \&_validate_package_name,

            # Limits
            'BWLIMIT'                              => $limit_validation_regex,
            'DISK_BLOCK_LIMIT'                     => $limit_validation_regex,
            'DISK_INODE_LIMIT'                     => $limit_validation_regex,
            'MAX_EMAIL_PER_HOUR'                   => $limit_validation_regex,
            'MAXADDON'                             => $limit_validation_regex,
            'MAXFTP'                               => $limit_validation_regex,
            'MAXLST'                               => $limit_validation_regex,
            'MAXMONGREL'                           => $limit_validation_regex,
            'MAXPARK'                              => $limit_validation_regex,
            'MAXPOP'                               => $limit_validation_regex,
            'MAXSQL'                               => $limit_validation_regex,
            'MAXSUB'                               => $limit_validation_regex,
            'QUOTA'                                => $limit_validation_regex,
            'MAX_EMAILACCT_QUOTA'                  => $limit_validation_regex,
            'EMAIL_OUTBOUND_SPAM_DETECT_THRESHOLD' => $limit_validation_regex,
            'MAXPASSENGERAPPS'                     => $limit_validation_regex,
            'MAX_TEAM_USERS'                       => $numeric_regex,            # MAX_TEAM_USERS does not support 'unlimited' as an option, only nums 1-7

            # Boolean values
            'DEMO'        => $boolean_validation_regex,
            'HASCGI'      => $boolean_validation_regex,
            'HASDKIM'     => $boolean_validation_regex,
            'HASSPF'      => $boolean_validation_regex,
            'UTF8MAILBOX' => $boolean_validation_regex,

            # Account protection options
            'MAX_DEFER_FAIL_PERCENTAGE'            => $limit_validation_regex,
            'MIN_DEFER_FAIL_TO_TRIGGER_PROTECTION' => $numeric_regex,

            'MXCHECK' => qr<\A(?:[0-9]+|$mxcheck_re_part)\z>,

            # Feature Data
            'STATGENS' => $comma_delimited_value_regex,

            'CREATED_IN_VERSION' => $version_number_regex,

            # Account enhancement values
            "$Whostmgr::AccountEnhancements::Constants::USERFILE_PREFIX" => $enhancement_id_regex,

            # Account hosting migration data
            Cpanel::Config::CpUser::MigrationData::KEY_UUID()                           => \&_validate_uuid,
            Cpanel::Config::CpUser::MigrationData::KEY_UUID_ADDED_AT_ACCOUNT_CREATION() => $boolean_validation_regex,
            Cpanel::Config::CpUser::MigrationData::KEY_TRANSFERRED_OR_RESTORED()        => $numeric_regex,
            Cpanel::Config::CpUser::MigrationData::KEY_INITIAL_SERVER_ENV_TYPE()        => $license_env_type_regex,
            Cpanel::Config::CpUser::MigrationData::KEY_INITIAL_SERVER_LICENSE_TYPE()    => $numeric_regex,
        };

        # Notification settings
        my $fields = Cpanel::CustInfo::Get::get_all_possible_contact_fields();
        foreach my $key ( keys %{$fields} ) {
            my $cpuser_key = $fields->{$key}{'cpuser_key'} || $key;
            if ( !$__cpuser_validation_hashref->{$cpuser_key} ) {
                $__cpuser_validation_hashref->{$cpuser_key} = sub {
                    my ( undef, $value ) = @_;

                    return 1 if !length $value;    # Empty values are allowed and should not generate a warning
                    if ( !$fields->{$key}{'validator'} || !ref $fields->{$key}{'validator'} || ref $fields->{$key}{'validator'} ne 'CODE' ) {

                        # case CPANEL-20559: This should never happen, but it did at least once
                        # so we now provide a suitable error in the hopes we can track this problem
                        # down.
                        return ( 0, "The value “$value” cannot be validated because there is no validator for “$key”." );
                    }
                    return $fields->{$key}{'validator'}->($value) ? 1 : ( 0, "The value of “$key” ($value) is invalid." );
                };
            }
        }

        foreach my $extension_key ( _get_package_extension_cpuser_keys() ) {
            $__cpuser_validation_hashref->{$extension_key} = \&_validate_third_party_value;
        }
    }

    return $__cpuser_validation_hashref;
}

#For testing.
sub _clear_validation_hashref {
    return $__cpuser_validation_hashref = undef;
}

sub _validate_feature_name {
    my ( $user, $value ) = @_;

    return Cpanel::Validate::FeatureList::is_valid_feature_list_name($value);
}

sub _validate_ssl_default_key_type ( $username, $value ) {
    my $ok = grep { $_ eq $value } (
        Cpanel::SSL::DefaultKey::Constants::USER_SYSTEM,
        Cpanel::SSL::DefaultKey::Constants::OPTIONS,
    );

    return $ok ? ($VALIDATE_OK) : ( $VALIDATE_SKIPPED, 'unknown value' );
}

sub _validate_child_workloads ( $username, $value ) {
    return $VALIDATE_OK if !$value;

    return ( $VALIDATE_SKIPPED, 'Child account backups should not be restored directly!' );
}

sub _validate_package_name {
    my ( $user, $name ) = @_;

    ##
    ## Package names are not required as the user may have been
    ## created by root with no package defined
    ##
    return $VALIDATE_OK if !length $name;

    my $err;
    try {
        Cpanel::Validate::PackageName::validate_or_die($name);
    }
    catch {
        $err = $_;
    };

    if ($err) {
        return ( $VALIDATE_SKIPPED, Cpanel::Exception::get_string($err) );
    }
    return $VALIDATE_OK;
}

sub _validate_mailbox_format {
    my ( $user, $value ) = @_;

    my $mailbox_format = $value;

    if ( !$Cpanel::Dovecot::Config::KNOWN_FORMATS{$mailbox_format} ) {
        return ( $VALIDATE_SKIPPED, Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” parameter must be one of the following: [join,~, ,_2]", [ 'MAILBOX_FORMAT', [ sort keys %Cpanel::Dovecot::Config::KNOWN_FORMATS ] ] )->to_string() );

    }
    return $VALIDATE_OK;
}

sub _validate_abs_path {
    my ( $user, $value ) = @_;

    return $VALIDATE_SKIPPED, 'Path must be absolute' if $value !~ m<\A/>;

    return _make_exception_func_validator( \&Cpanel::Validate::FilesystemPath::die_if_any_relative_nodes )->( $user, $value );
}

sub _make_exception_func_validator {
    my ($fatal_func) = @_;

    return sub {
        my ( $user, $value ) = @_;

        my $err;
        try {
            $fatal_func->($value);
        }
        catch {
            $err = $_;
        };
        if ($err) {
            return ( $VALIDATE_SKIPPED, Cpanel::Exception::get_string($err) );
        }
        return $VALIDATE_OK;
    };
}

sub _validate_third_party_value {
    my ( $user, $value ) = @_;

    my $third_party_value_regex = qr{\A[0-9a-zA-Z\._, \t-]+\z};

    if ( !length $value ) {
        return $VALIDATE_OK;
    }

    if ( $value !~ $third_party_value_regex ) {
        return ( $VALIDATE_SKIPPED, "The value '$value' is invalid." );
    }

    return $VALIDATE_OK;
}

sub _validate_contactemail {
    my ( $user, $contact_email ) = @_;

    # if the backup doesn't have a contact email set, prefer whatever was created from CreateAccount
    if ( !$contact_email ) {
        return ( $VALIDATE_DISCARD, 'A contact email address is not specified for this backup. For this reason, the unspecified value will be skipped in order to give preference to values that may have already been restored.' );
    }
    return $VALIDATE_OK if Cpanel::Validate::EmailRFC::is_valid($contact_email);

    return ( $VALIDATE_SKIPPED, "The contact email '$contact_email' is invalid." );
}

sub _validate_domain {
    my ( $user, $domain ) = @_;

    return ( $VALIDATE_SKIPPED, 'The domain value is not set.' ) if !length $domain;
    return $VALIDATE_OK                                          if Cpanel::Validate::Domain::is_valid_cpanel_domain($domain);
    return ( $VALIDATE_SKIPPED, "The domain value '$domain' is invalid." );
}

sub _validate_uuid {
    my ( $user, $uuid ) = @_;

    return _make_exception_func_validator( \&Cpanel::Validate::UUID::validate_uuid_or_die )->( $user, $uuid );
}

my $_locale;

sub _locale {
    return $_locale ||= do {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
        Cpanel::Locale->get_handle();
    };
}

1;
