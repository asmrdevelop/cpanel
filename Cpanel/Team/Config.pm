package Cpanel::Team::Config;

# cpanel - Cpanel/Team/Config.pm                   Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::AccessIds                      ();
use Cpanel::AcctUtils::DomainOwner::Tiny   ();
use Cpanel::AcctUtils::Domain              ();
use Cpanel::AcctUtils::Suspended           ();
use Cpanel::Auth::Generate                 ();
use Cpanel::Autodie                        ();
use Cpanel::Autodie::Unlink                ();
use Cpanel::Config::LoadCpUserFile         ();
use Cpanel::Config::Session                ();
use Cpanel::Exception                      ();
use Cpanel::FileUtils::Touch               ();
use Cpanel::FtpUtils                       ();
use Cpanel::Locale                         ();
use Cpanel::PwCache                        ();
use Cpanel::SafeDir::RM                    ();
use Cpanel::SafeFile                       ();
use Cpanel::SafeFile::Replace              ();
use Cpanel::Security::Authn::TwoFactorAuth ();
use Cpanel::Session::SinglePurge           ();
use Cpanel::Server::Type                   ();
use Cpanel::Team::Constants                ();
use Cpanel::Team::Queue                    ();
use Cpanel::Validate::Domain               ();
use Cpanel::Validate::EmailRFC             ();
use Cpanel::Validate::Username             ();
use Date::Parse                            qw( str2time );

my $cp_config;

=encoding utf-8

=head1 NAME

Cpanel::Team::Config

=head1 DESCRIPTION

Module to manage team configuration file:  /var/cpanel/team/<team-owner>

 File format:
 <team-owner>
 <team-user1>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>,<secondary-contact-email>:<subacct_guid>:<locale>:<suspend-date>,<suspend-reason>:<expire-date>,<expire-reason>
 <team-user2>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>,<secondary-contact-email>:<subacct_guid>:<locale>:<suspend-date>,<suspend-reason>:<expire-date>,<expire-reason>

File starts with team-owner's cPanel account username on a line by itself.
This is so anyone looking at the file will know what team it belongs to. It
also helps detect a corrupt file.  The name of the file should be the same as
the team-owner cPanel account username.

Each line after the first line contains information about a team-user.  Fields
are colon-delimited and defined as follows:

<team-user1>   Team-user's account username.  This is the name used when
logging in without the domain portion.

<notes>        The notes field can be used for any purpose by the team-owner.
Typically it might contain the name of the person whose account it is, but can
contain any information.  e.g. phone, nickname, hat size, and/or favorite color.
It is not considered protected data and is not classified as secure.  A team
member should not put sensitive information in this field.

<role1>,<role2>,...
               List of roles <team-user1> is assigned.  The list is
comma-delimited. Valid roles are not currently defined.

<password>     Encrypted password for <team-user1>

<create-date>  Date account was created.  Please note that all dates are Unix
Epoch Time, the number of seconds since January 1, 1970.

<contact-email>
               <team-user1>'s external email address.  This email is used for
resetting passwords.

<secondary-contact-email>
               <team-user1>'s alternate external email address.

<subacct_guid>  This is the unique identifier for the subaccount the team user
controls, giving them access and control over at most one of each of 3 services:
FTP, Web Disk, and email. It's a sha256_hex hash based off of the hostname,
type of subaccount, and random characters. Team Manager HTML encodes the GUID
delimiter to '%3a' for Config file storage, but loads and uses the User Manager
format of ':'.

Example:
A%3aUM5.TEST%3a63A1D27F%3aEFCE06D8250093CBCB5E0DC33AA55CE4291BE482E734875EE8426D3A87FFCACB

<locale>  Team-user locale string.  If empty, the team-owner's locale will be
used.

<suspend-date> Date account was suspended in Unix Epoch Time.  If the field is
empty the account is not suspended.

<suspend-reason> Optional text giving reason for suspension.  Only present if
<suspend-date> is there.

<expire-date> Date of expiration of account in Unix Epoch Time.  If the field is
empty the account is not expired and has no scheduled expire date.  If date is
in the future then there should be an expiration task in the queue.  If the date
is in the past then the account has expired and the password should be disabled.

<expire-reason> Optional text giving reason for expire.  Only present if
<expire-date> is there.

Format is similar to /etc/passwd.  No need for separate shadow file.

All 'set', 'add', 'remove', 'enable', 'disable', '[un]suspend', and expire methods
below use file locking to prevent collisions when writing to configuration
file.

=head1 METHODS

=over

=item * new -- Creates a team object.

    If this is the first team on this server, creates the team config directory:
        /var/cpanel/team/

    Creates the team configuration file if it does not already exist:
        /var/cpanel/team/$team_owner

    Inserts $team_owner as the first line in the file.

    Checks the version of an existing team configuration file.  If not current,
    it brings it up to the current version.

    RETURNS: Team object
        This object will be needed for all further methods.

    ERRORS
        All failures are fatal.
        Fails if $team_owner is not a real cPanel account.
        Fails if cannot create or access configuration file or /var/cpanel/team directory.

    EXAMPLE
        my $team_obj = Cpanel::Team::Config->new($team_owner);

=cut

sub new {
    my ( $class, $team_owner ) = @_;

    if ( !Cpanel::Server::Type::has_feature('teams') ) {
        die Cpanel::Exception::create( 'FeatureNotEnabled', 'The “[_1]” feature is not available. Ask your reseller about adding this feature.', ['Team Manager'] );
    }

    _validate_name($team_owner);
    if ( !Cpanel::Validate::Username::user_exists($team_owner) ) {
        die Cpanel::Exception::create( 'UserNotFound', [ name => $team_owner ] );
    }

    Cpanel::Autodie::mkdir_if_not_exists( $Cpanel::Team::Constants::TEAM_CONFIG_DIR, 0755 );

    my $config_file = "$Cpanel::Team::Constants::TEAM_CONFIG_DIR/$team_owner";

    if ( !-e $config_file ) {
        my $config_fh;
        Cpanel::FileUtils::Touch::touch_if_not_exists($config_file);
        Cpanel::Autodie::chmod( 0640, $config_file );

        my $config_lock = Cpanel::SafeFile::safeopen( $config_fh, '+<', $config_file )
          or die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $config_file, error => $!, mode => '+<' ] );
        my @content = ("$team_owner $Cpanel::Team::Constants::LATEST_CONFIG_VERSION\n");
        Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, @content );

        _safeclose_groupuser( { config_file => $config_file }, $config_fh, $config_lock );
    }
    else {
        Cpanel::Autodie::open( my $FH, '<', $config_file );
        my $header = <$FH>;
        close $FH;
        my ( $team_owner, $version ) = ( split( /[ \n]+/, $header ), '' );

        if ( $version ne $Cpanel::Team::Constants::LATEST_CONFIG_VERSION ) {
            require Cpanel::Team::Config::Version;
            Cpanel::Team::Config::Version::update( $team_owner, $Cpanel::Team::Constants::LATEST_CONFIG_VERSION )
              or die Cpanel::Exception::create( 'CorruptFile', 'Team configuration file “[_1]” is corrupt.', [$config_file] );
        }
    }

    my $self = {
        config_file => $config_file,
        team_owner  => $team_owner,
    };

    return bless $self, $class;
}

sub _validate_name {
    if ( !length $_[0] ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The username validation routine received an empty username.' );
    }
}

sub _validate_roles {
    my @roles = @_;

    foreach my $role (@roles) {

        # skipping the empty role as UI can also send empty role in set_roles
        next if !$role;
        if ( !exists $Cpanel::Team::Constants::TEAM_ROLES{$role} ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'Unknown role “[_1]”.', [$role] );
        }
    }
    return;
}

=item * load -- Opens the team configuration file and loads it into a multi-level hash structure.

    RETURNS: Team hash as follows

    $team = { owner   => 'towner_username',
              version => 'v1.0',
              users => { 'george' => { notes          => 'George Washington',
                                       roles          => [ 'Email', 'Files' ],
                                       password       => '$6$30cnP.OMshI8PBm2$BBoh', # Encrypted password
                                       created        => 1648552421,
                                       contact_email  => 'gwash@whitehouse.gov',
                                       secondary_contact_email => 'gwash@mailinator.com',
                                       subacct_guid   => 'GEORGE:OWNER.DOMAIN:63B97924:11F49CF5DD530D87A818ED5654A4229EAE772B68237B853C051382E63893587C',
                                       locale         => 'en',
                                       lastlogin      => 164845325,
                                       suspend_date   => '',
                                       suspend_reason => '',
                                       expire_date    => '',
                                       expire_reason  => '', },
                         'theman' => { notes          => 'Stan Lee',
                                       roles          => [ 'Domains' ],
                                       password       => '$6$rz7VcL.l0tHEZ0Bs', # Encrypted password
                                       created        => 1643552990,
                                       contact_email  => 'theman@marvel.com',
                                       secondary_contact_email => 'theman@mailinator.com',
                                       subacct_guid   => 'THEMAN:OWNER.DOMAIN:63B99247:11F49CF5DD530D87A818ED5654A4229EAE772B68237B853C051382E63893587C',
                                       locale         => 'en',
                                       lastlogin      => 164854251,
                                       suspend_date   => 1648576562,
                                       suspend_reason => 'bad karma',
                                       expire_date    => '',
                                       expire_reason  => '', },
            },
    };

    ERRORS
        All failures are fatal.
        Fails if team configuration file cannot be opened or is corrupt.

    EXAMPLE
        my $team = $team_obj->load();

=cut

sub load {
    my ($self) = @_;

    Cpanel::Autodie::open( my $FH, '<', $self->{config_file} );
    chomp( my @config = <$FH> );
    close $FH;

    return $self->_parse_config(@config);
}

# Turn file lines into a perl hash structure
sub _parse_config {
    my ( $self, $header, @config ) = @_;    # $header is the first element of @config.  This saves a shift().
    my ( $team_owner, $version ) = ( split( /\s+/, $header ), '' );

    my ($team_file) = $self->{config_file} =~ m{([^/]+)$};
    if ( $team_owner ne $team_file ) {
        die Cpanel::Exception::create( 'CorruptFile', 'Team configuration file “[_1]” is corrupt.', [ $self->{config_file} ] );
    }

    my $team = {
        owner   => $team_owner,
        version => $version,
        users   => {},
    };
    validate_config_fields( \@config, $self->{config_file} );

    foreach my $team_user_record (@config) {
        my ( $team_user_name, $notes, $roles, $password, $creation, $contact, $subacct_guid, $locale, $suspend, $expire ) = split /:/, $team_user_record;
        my ( $primary_contact_email, $secondary_contact_email ) = ( ( split /,/, $contact || ',', 2 ), '' );
        my @roles = split /,/, $roles;
        my ( $suspend_date, $suspend_reason ) = ( ( split /,/, $suspend || ',', 2 ), '' );    # Ensure suspend reason is never undef.
        my ( $expire_date,  $expire_reason )  = ( ( split /,/, $expire  || ',', 2 ), '' );    # Ensure expire reason is never undef.
        $team->{users}{$team_user_name} = {
            notes                   => _decode($notes),
            roles                   => [@roles],
            password                => $password,
            created                 => $creation,
            contact_email           => $primary_contact_email,
            secondary_contact_email => $secondary_contact_email,
            subacct_guid            => _decode($subacct_guid),
            locale                  => $locale,
            lastlogin               => eval { _get_lastlogin_time( $team_owner, $team_user_name ); } || '',
            suspend_date            => $suspend_date,
            suspend_reason          => _decode($suspend_reason),
            expire_date             => $expire_date,
            expire_reason           => _decode($expire_reason),
        };
    }

    return $team;
}

=item * validate_config_fields -- Validates team config fields.

    RETURNS: does not return anything.

    ERRORS
        All failures are fatal.
        Fails if the team users with roles count exceeds the max_team_users_with_roles count.
        Fails if the file is missing a field.
        Fails if length of any one of the following fields username, notes, subacct_guid, suspend_reason or expire reason are over the limit.
        Fails if the creation date, suspend date or expire date is not a valid date.
        Fails if the contact_email is not a valid email address.
        Fails if the secondary_contact_email is not a valid email address. Ignores if it is empty.
        Fails if the roles are invalid.
        Fails if the password field is blank.
        Fails if the locale passed is not a valid cPanel locale.

    EXAMPLE
        Cpanel::Team::Config::validate_config_fields( \@config, $config_file );

=cut

sub validate_config_fields {
    my ( $config_ref, $config_file ) = @_;

    my $team_owner = ( split '/', $config_file )[-1];
    {
        local $" = "\n";
        my $team_users_with_roles_cnt = my @all_roles = "@$config_ref" =~ /^[^:]+:[^:]*:([^:]+):/gm;
        my $max_team_users_with_roles = max_team_users_with_roles_count($team_owner);
        if ( $team_users_with_roles_cnt > $max_team_users_with_roles ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Team already has “[_1]” team users with roles. This exceeds the maximum number of team users with roles count, “[_2]”.', [ scalar( @{$config_ref} ), $max_team_users_with_roles ] );
        }
    }

    my $line_number = 1;
    foreach my $team_user_record ( @{$config_ref} ) {
        $line_number++;
        my $delimiter_cnt = $team_user_record =~ tr /://;
        if ( $delimiter_cnt != 9 ) {
            die Cpanel::Exception::create( 'CorruptFile', 'Team configuration file “[_1]” is corrupt and does not have the expected number of fields on line “[_2]”.', [ $config_file, $line_number ] );
        }
        my ( $team_user_name,        $notes, $roles, $password, $creation, $contact, $subacct_guid, $locale, $suspend, $expire ) = split /:/, $team_user_record;
        my ( $suspend_date,          $suspend_reason )          = ( ( split /,/, $suspend || ',', 2 ), '' );    # Ensure reason is never undef.
        my ( $primary_contact_email, $secondary_contact_email ) = ( ( split /,/, $contact || ',', 2 ), '' );
        my ( $expire_date,           $expire_reason )           = ( ( split /,/, $expire  || ',', 2 ), '' );    # Ensure reason is never undef.
        $delimiter_cnt = $subacct_guid =~ s/%3a/%3a/g;

        # If $subacct_guid is going to have something in it, it must have 3 x "%3a".
        if ( $delimiter_cnt != 3 && $delimiter_cnt != 0 ) {
            die Cpanel::Exception::create( 'CorruptFile', 'The Team configuration file “[_1]” has a subacct_guid section with an incorrect number of fields on line “[_2]”.', [ $config_file, $line_number ] );
        }
        if ( length $team_user_name > 16 ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Username field contains “[_1]” characters on line “[_2]”. The limit is “[_3]” characters.', [ length($team_user_name), $line_number, 16 ] );
        }
        if ( length $notes > $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Notes field contains “[_1]” characters on line “[_2]”. The limit is “[_3]” characters.', [ length($notes), $line_number, $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ] );
        }
        if ( length $suspend_reason > $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Suspend Reason field contains “[_1]” characters on line “[_2]”. The limit is “[_3]” characters.', [ length($suspend_reason), $line_number, $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ] );
        }
        if ( length $expire_reason > $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Expire Reason field contains “[_1]” characters on line “[_2]”. The limit is “[_3]” characters.', [ length($expire_reason), $line_number, $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ] );
        }
        if ( !Cpanel::Validate::EmailRFC::is_valid_remote($primary_contact_email) ) {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid contact email address on line “[_2]”.', [ $primary_contact_email, $line_number ] );
        }
        if ( $secondary_contact_email && !Cpanel::Validate::EmailRFC::is_valid_remote($secondary_contact_email) ) {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid contact email address on line “[_2]”.', [ $secondary_contact_email, $line_number ] );
        }
        if ( $creation !~ /^(?:\d{10})?$/ ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Create date field does not have a valid epoch date: “[_1]” on line “[_2]”.', [ $creation, $line_number ] );
        }
        if ( $suspend_date !~ /^(?:\d{10})?$/ ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Suspend date field does not have a valid epoch date: “[_1]” on line “[_2]”.', [ $suspend_date, $line_number ] );
        }
        if ( $expire_date !~ /^(?:\d{10})?$/ ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Expire date field does not have a valid epoch date: “[_1]” on line “[_2]”.', [ $expire_date, $line_number ] );
        }
        if ( !length $password ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Password field is blank on line “[_1]”.', [$line_number] );
        }

        $locale = _validate_locale($locale);

        # TODO check if there's a subacct_guid max size requirement
        if ( length $subacct_guid > $Cpanel::Team::Constants::MAX_TEAM_GUID_SIZE ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Subaccount GUID field contains “[_1]” characters on line “[_2]”. The limit is “[_3]” characters.', [ length($subacct_guid), $line_number, $Cpanel::Team::Constants::MAX_TEAM_GUID_SIZE ] );
        }
        _validate_roles( split /,/, $roles ) if length($roles);
    }
    return;
}

# Turn $team perl hash structure into file lines.
sub _unparse_config {
    my ( $self, $team ) = @_;

    my @config = ( join( ' ', grep { length } @{$team}{qw(owner version)} ) . "\n" );
    foreach my $team_user ( sort keys %{ $team->{users} } ) {
        my $tu = $team->{users}->{$team_user};    # Simplify code below
        $tu->{notes}         = _encode( $tu->{notes} );
        $tu->{subacct_guid}  = _encode( $tu->{subacct_guid} );
        $tu->{roles}         = join ',', @{ $tu->{roles} };
        $tu->{contact_email} = $tu->{contact_email} . "," . $tu->{secondary_contact_email};
        $tu->{suspended}     = $tu->{suspend_date} . ',' . _encode( $tu->{suspend_reason} );
        $tu->{expire}        = $tu->{expire_date} . ',' . _encode( $tu->{expire_reason} );
        my $entry = join ':', $team_user, map { $_ // '' } @{$tu}{qw(notes roles password created contact_email subacct_guid locale suspended expire)};
        push @config, "$entry\n";
    }

    return @config;
}

=item * load_array -- Opens the team configuration file and loads it into an array structure.

    Does the exact same thing as load() except that its return is primarily an array instead of a hash.

    RETURNS: Team array as follows

    $team = [ { username       => 'george',
                notes          => 'George Washington',
                roles          => [ 'Email', 'Files' ],
                password       => '$6$30cnP.OMshI8PBm2$BBoh', # Encrypted password
                created        => 1648552421,
                contact_email  => 'gwash@whitehouse.gov',
                secondary_contact_email => 'gwash@mailinator.com',
                subacct_guid   => 'GEORGE:OWNER.DOMAIN:63B97924:11F49CF5DD530D87A818ED5654A4229EAE772B68237B853C051382E63893587C',
                locale         => 'en',
                lastlogin      => 164845325,
                suspend_date   => '',
                suspend_reason => '',
                expire_date    => '',
                expire_reason  => '', },
              { username       => 'theman',
                notes          => 'Stan Lee',
                roles          => [ 'Domains' ],
                password       => '$6$rz7VcL.l0tHEZ0Bs', # Encrypted password
                created        => 1643552990,
                contact_email  => 'theman@marvel.com',
                secondary_contact_email => 'theman@mailinator.com',
                subacct_guid   => 'THEMAN:OWNER.DOMAIN:63B99247:11F49CF5DD530D87A818ED5654A4229EAE772B68237B853C051382E63893587C',
                locale         => 'en',
                lastlogin      => 164854251,
                suspend_date   => 1648576562,
                suspend_reason => 'Bad karma',
                expire_date    => '',
                expire_reason  => '', },
              },
            ];

    ERRORS
        All failures are fatal.
        Fails if team configuration file cannot be opened or is corrupt.

    EXAMPLE
        my $team = $team_obj->load_array();

=cut

sub load_array {
    my ($self) = @_;
    my $team_hash_ref = $self->load();

    my $team = [];
    foreach my $team_user ( sort keys %{ $team_hash_ref->{users} } ) {
        $team_hash_ref->{users}->{$team_user}->{username} = $team_user;
        push @$team, $team_hash_ref->{users}->{$team_user};
    }

    return $team;
}

=item * get_team_user -- Opens the team configuration file, finds team-user
                         entry, and returns team-user record in a hash.

    ARGUMENTS
        team_user (String) -- Can be either the team-user account name or the
                         login.  The login includes the team-user username
                         with its team-owner's primary domain.
                         e.g. user@domain.com

    RETURNS: User hash as follows

    $team_user = { notes          => 'George Washington',
                   roles          => [ 'Email', 'Files' ],
                   password       => '$6$30cnP.OMshI8PBm2$BBoh', # Encrypted password
                   created        => 1648552421,
                   contact_email  => 'gwash@whitehouse.gov',
                   secondary_contact_email => 'gwash@mailinator.com',
                   subacct_guid   => 'GEORGE:OWNER.DOMAIN:63B97924:11F49CF5DD530D87A818ED5654A4229EAE772B68237B853C051382E63893587C',
                   locale         => 'en',
                   suspend_date   => '',
                   suspend_reason => '',
                   expire_date    => '',
                   expire_reason  => '',
       };

    ERRORS
        All failures are fatal.
        Fails if team configuration file cannot be opened or is corrupt.
        Fails if team-user does not exist for team owner.
        Fails if team-user login domain is invalid.
        Fails if team-owner does not exist.

    EXAMPLES
        # Can be called in either of two ways.
        # 1.  Called with a team object, team-user has no domain
        my $team_user = $team_obj->get_team_user('george');

        # 2.  Called without a team object using a team-user login (with domain)
        my $team_user = get_team_user('george@wh.org');

        # Can also direct access an individual field or a group of fields as follows:
        my $notes = $team_obj->get_team_user('george')->{notes};
        my ($notes, $pw) = @{get_team_user('george@wh.org')}{qw(notes password)};
=cut

sub get_team_user {
    my @args = @_;
    my ( $self, $username, $domain, $login );

    if ( @args == 1 ) {    # Called with login
        $login = $args[0];
        ( $username, $domain ) = split /@/, $login;

        _check_domain_format($domain);
        my $team_owner = _get_domain_owner($domain);
        _check_primary_domain( $team_owner, $domain );

        $self = Cpanel::Team::Config->new($team_owner);
    }
    elsif ( @args == 2 ) {    # Called as method with team object
        ( $self, $username ) = @args;
    }
    else {
        die Cpanel::Exception::create( 'InvalidParameter', 'Expecting team object and username, or team user login with domain. Instead found “[_1]”.', [ join ", ", @args ] );
    }

    my $team = $self->load();
    if ( !exists $team->{users}->{$username} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$username] );
    }
    return $team->{users}->{$username};
}

=item * get_team_user_roles -- Opens the team configuration file, finds team-user
                         entry, and returns the roles from the team-user record in an array

    ARGUMENTS
        team_user (String) -- The team-user account name.

    RETURNS: User roles array ref as follows

    $roles_ref = [ 'Email', 'Files' ];

    ERRORS
        All failures are fatal.
        Fails if team configuration file cannot be opened or is corrupt.
        Fails if team-user does not exist.
        Fails if team-user does not exist for team owner.
        Fails if team-user login domain is invalid.
        Fails if team-owner does not exist.

    EXAMPLE
        $roles_ref = $team_obj->get_team_user_roles( $team_user );

=cut

sub get_team_user_roles {
    my ( $self, $username ) = @_;

    my $team = $self->load();
    if ( !defined $username || !exists $team->{users}->{$username} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$username] );
    }
    return $team->{users}->{$username}->{roles};
}

=item * get_team_info -- Returns team hash.

    ARGUMENTS
        team_user    (String) -- team user name
        owner_domain (String) -- any one of the team owner's domains

    RETURNS: Team hash

    ERRORS
        All failures are fatal.
        Fails if domain given is not a valid cPanel domain.
        Fails if the team user given does not exist.

    EXAMPLE
        my $team = Cpanel::Team::Config::get_team_info( $team_user, $owner_domain );

=cut

sub get_team_info {
    my ( $team_user, $owner_domain ) = @_;

    _check_domain_format($owner_domain);
    my $team_owner = _get_domain_owner($owner_domain);
    _check_primary_domain( $team_owner, $owner_domain );

    my $team_obj = Cpanel::Team::Config->new($team_owner);
    my $team     = $team_obj->load();

    if ( !_check_team_user_exists( $team, $team_user ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }
    return $team;
}

=item * add_team_user -- Validates inputs and saves new team-user information to team configuration file.

    user, contact_email are required.  expire_date is in Unix Epoch Time.  If
    an expire_reason is given with no expire_date then expire_reason is
    ignored. Any suspend data provided will be ignored.

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if required data is missing or if any data is obviously wrong.
        Fails if username already in use.
        Fails if already at the maximum number of team-users.
        Fails if cannot read or write to team configuration file.

    EXAMPLE
    my $results = $team_obj->add_team_user( user          => 'john',
                                            password      => 'trustNo0ne!',    # Unencrypted password string (optional)
                                            contact_email => 'pinky@raidersfans.net',
                                            roles         => 'email,web',      # optional field
                                            locale        => 'en',             # optional field
                                            expire_date   => 1668462560,       # optional field
                                            expire_reason => "Contract ends",  # optional field
       );

    # Note that user and contact_email fields are required.

=cut

sub add_team_user {
    my ( $self, %team_user_info ) = @_;

    if ( !exists $team_user_info{user} ) {
        die Cpanel::Exception::create( 'MissingParameter', 'No username.' );
    }
    _validate_name( $team_user_info{user} );

    if ( !Cpanel::Validate::Username::is_strictly_valid( $team_user_info{user} ) ) {
        die Cpanel::Exception::create( 'InvalidUsername', [ value => $team_user_info{user} ] );
    }

    if ( defined $team_user_info{notes} ) {
        if ( length $team_user_info{notes} > $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Notes field contains “[_1]” characters. The limit is “[_2]” characters.', [ length( $team_user_info{notes} ), $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ] );
        }
        $team_user_info{notes} = _encode( $team_user_info{notes} );
    }
    $team_user_info{password} = Cpanel::Auth::Generate::generate_password_hash( $team_user_info{password} );
    _validate_roles( split /,/, $team_user_info{roles} ) if defined $team_user_info{roles};
    foreach my $field (qw(contact_email secondary_contact_email services locale)) {
        $team_user_info{$field} //= '';
        if ( exists $team_user_info{$field} && $team_user_info{$field} =~ /([:\n])/ ) {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” not allowed in “[_2]”.', [ ( $1 eq ':' ? 'Colon' : 'Line Feed' ), $field ] );
        }
    }

    my $now = time;
    if ( defined $team_user_info{expire_date} ) {
        if ( $team_user_info{expire_date} =~ /\D/ ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Expire date field contains non-Unix Epoch date characters “[_1]”.', [ $team_user_info{expire_date} ] );
        }
        elsif ( $team_user_info{expire_date} =~ /^(?:\d{10})?$/ ) {    # This code will be wrong beginning Sat Nov 20 17:46:40 2286.
            if ( length $team_user_info{expire_reason} > $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ) {
                die Cpanel::Exception::create( 'InvalidParameter', 'The Expire Reason field contains “[_1]” characters. The limit is “[_2]” characters.', [ length( $team_user_info{expire_reason} ), $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ] );
            }
            $team_user_info{expire} = $team_user_info{expire_date} . ',' . _encode( $team_user_info{expire_reason} );
        }
        if ( $team_user_info{expire_date} <= $now ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The expiration date is in the past.' );
        }
    }
    else {
        @team_user_info{qw(expire_date expire_reason)} = ( '', '' );    # If expire_date doesn't exist we don't care about expire_reason.
    }

    my $team = $self->load();
    if ( exists $team->{users}->{ $team_user_info{user} } ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Team user “[_1]” already exists.', [ $team_user_info{user} ] );
    }
    is_unique_name( $team->{owner}, $team_user_info{user} );
    my $max_users_with_roles = max_team_users_with_roles_count( $team->{owner} );
    my $users_with_roles     = grep { @{ $team->{users}{$_}{roles} } } keys %{ $team->{users} };
    if ( defined $team_user_info{roles} && length $team_user_info{roles} && $users_with_roles >= $max_users_with_roles ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Maximum of “[_1]” team users with roles reached. Cannot add a team user with a role.', [$max_users_with_roles] );
    }

    if ( !Cpanel::Validate::EmailRFC::is_valid_remote( $team_user_info{contact_email} ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid email address.', [ $team_user_info{contact_email} ] );
    }
    if ( $team_user_info{secondary_contact_email} && !Cpanel::Validate::EmailRFC::is_valid_remote( $team_user_info{secondary_contact_email} ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid email address.', [ $team_user_info{secondary_contact_email} ] );
    }
    $team_user_info{contact} = "$team_user_info{contact_email},$team_user_info{secondary_contact_email}";

    # list of service params we'll pass on to UserManager
    my %svc_labels = (
        ftp     => [ 'enabled', 'homedir', 'quota' ],
        webdisk => [ 'enabled', 'homedir', 'perms', 'enabledigest', 'private' ],
        email   => [ 'enabled', 'quota' ],
    );
    if ( defined $team_user_info{services} && length $team_user_info{services} ) {
        for my $svc ( keys %svc_labels ) {
            if ( exists $team_user_info{services}{$svc} ) {
                my $svc_hr = $team_user_info{services}{$svc};

                for my $parameter ( keys %{$svc_hr} ) {
                    if ( grep { $_ eq $parameter } @{ $svc_labels{$svc} } ) {
                        if ( $parameter eq 'enabled' && $svc_hr->{enabled} !~ /^(?:[01]?)$/ ) {
                            die Cpanel::Exception::create( 'InvalidParameter', '[asis,Services] [_1] enabled value is invalid “[_2]”. Must be 0, 1, or an empty string.', [ $svc, $svc_hr->{enabled} ] );
                        }
                        elsif ( $parameter eq 'homedir' ) {

                            # die if webdisk or ftp path has a null char, or if webdisk path is empty
                            if ( $svc_hr->{homedir} =~ /\c@/
                                || ( $svc eq 'webdisk' && $svc_hr->{homedir} eq '' ) ) {
                                die Cpanel::Exception::create( 'InvalidParameter', '[asis,Services] [_1] homedir value is invalid “[_2]”. Must be a valid file path.', [ $svc, $svc_hr->{homedir} ] );
                            }
                        }
                        elsif ( $parameter eq 'quota' && $svc_hr->{quota} !~ /^(?:\d*|unlimited)$/ ) {
                            die Cpanel::Exception::create( 'InvalidParameter', '[asis,Services] [_1] value is invalid “[_2]”. Must be an integer, unlimited, or an empty string.', [ $svc, $svc_hr->{quota} ] );
                        }
                        elsif ( $parameter eq 'perms' && $svc_hr->{perms} !~ /^(?:ro|rw|)$/ ) {
                            die Cpanel::Exception::create( 'InvalidParameter', '[asis,Services] [_1] value is invalid “[_2]”. Must be ‘[asis,ro]’, ‘[asis,rw]’, or an empty string.', [ $svc, $svc_hr->{perms} ] );
                        }
                    }
                    else {
                        die Cpanel::Exception::create( 'InvalidParameter', '[_1] is not a valid parameter for services “[_2]”.', [ $parameter, $svc ] );
                    }
                }
            }
        }
    }

    $team_user_info{suspend} = ',';
    $team_user_info{expire}  = "$team_user_info{expire_date},$team_user_info{expire_reason}";
    $team_user_info{create}  = $now;
    $team_user_info{locale}  = $cp_config->{LOCALE};                                            # Use team-owner's current locale.
    my $entry = join ':', map { $_ // '' } @team_user_info{qw(user notes roles password create contact subacct_guid locale suspend expire)};

    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    @content = map { "$_\n" } @content, $entry;
    @content[ 1 .. $#content ] = sort @content[ 1 .. $#content ];
    Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );
    my $results = $self->_safeclose_groupuser( $config_fh, $config_lock );

    if ( $team_user_info{expire_date} ) {
        my $expire_command = "/usr/local/cpanel/bin/expire_team_user $self->{team_owner} $team_user_info{user}";
        my $team_q_obj     = Cpanel::Team::Queue->new();
        $team_q_obj->queue_task( $team_user_info{expire_date}, $self->{team_owner}, $team_user_info{user}, $expire_command )
          or die Cpanel::Exception::create( 'ProcessFailed', 'Unable to queue expire task for team user “[_1]”.', [ $team_user_info{user} ] );
    }
    return $results;
}

=item * set_team_user_guid -- Replaces current team user GUID field with new team user GUID.

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.

    EXAMPLE
        my $results = $team_obj->set_team_user_guid( 'bobby', 'BOBBY:TEAMOWNER.TLD:A2345678:A234567890B234567890C234567890D234567890E234567890F234567890G123' );

=cut

sub set_team_user_guid {
    my ( $self, $team_user, $guid ) = @_;

    _validate_name($team_user);

    # TODO? _validate_guid($team_user)

    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);
    if ( !_check_team_user_exists( $team, $team_user ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    $team->{users}->{$team_user}->{subacct_guid} = $guid;
    @content = $self->_unparse_config($team);
    Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );

    return $self->_safeclose_groupuser( $config_fh, $config_lock );
}

=item * is_unique_name -- Checks team username against existing virtual account names - email, Web Disk, FTP.

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if there is a match. New team usernames cannot be the same as existing virtual accounts, due to conflicts during session deletion.

    EXAMPLE
		is_unique_name( $team_owner, $team_user );

=cut

sub is_unique_name {
    my ( $team_owner, $team_user ) = @_;
    my $home_dir = ( Cpanel::PwCache::getpwnam($team_owner) )[7];
    my $domain   = Cpanel::AcctUtils::Domain::getdomain($team_owner);
    my $login    = "$team_user\@$domain";

    # needed to get around logger usage, see Cpanel::MemUsage::Apps::Banned
    require Cpanel::Email::Exists;
    require Cpanel::WebDisk;

    # Email
    if ( Cpanel::Email::Exists::pop_exists_specify_homedir( $team_user, $domain, $home_dir ) ) {
        die Cpanel::Exception::create( 'NameConflict', 'The username is already being used by an email account.' );
    }

    # WebDisk
    my @response = Cpanel::WebDisk::api2_listwebdisks( check_primary_domain => 1, home_dir => $home_dir, );
    if (@response) {
        if ( grep { $_->{login} eq $login } @response ) {
            die Cpanel::Exception::create( 'NameConflict', 'The username is already being used by a [asis,Web Disk] account.' );
        }
    }

    # FTP
    if ( grep { $_->{user} eq $login } Cpanel::FtpUtils::listftp($team_owner) ) {
        die Cpanel::Exception::create( 'NameConflict', 'The username is already being used by an FTP account.' );
    }

    return 1;
}

sub is_valid_max_team_users_with_roles {
    my $max = shift;

    if (   defined $max
        && $max =~ /^\d+$/
        && $max >= 0
        && $max <= $Cpanel::Team::Constants::MAX_TEAM_USERS_WITH_ROLES ) {
        return 1;
    }

    return 0;
}

=item * max_team_users_with_roles_count -- Returns actual maximum for this team.

    Compares cP user file at /var/cpanel/users/<team-owner> for MAX_TEAM_USER
    field with system maximum at
    $Cpanel::Team::Constants::MAX_TEAM_USERS_WITH_ROLES.

    RETURNS:  returns the lesser of the two: MAXi_TEAM_USER and MAX_TEAM_USERS_WITH_ROLES.

    ERRORS
        All failures are fatal.
        Fails if cannot read the cP user file.
        Fails if $team_owner does not exist.
        Fails if cP user file field MAX_TEAM_USER is invalid.

    EXAMPLE
        my $max = max_team_users_with_roles_count( $team_owner );

=cut

sub max_team_users_with_roles_count {
    my $team_owner = shift;
    $cp_config = Cpanel::Config::LoadCpUserFile::load_or_die($team_owner);

    # TODO:  Modify /var/cpanel/users/<user> file to use MAX_TEAM_USERS_WITH_ROLES instead of MAX_TEAM_USERS.  Might not be worth the bother.
    if ( is_valid_max_team_users_with_roles( $cp_config->{MAX_TEAM_USERS} ) ) {
        return $cp_config->{MAX_TEAM_USERS};
    }
    return $Cpanel::Team::Constants::MAX_TEAM_USERS_WITH_ROLES;
}

# Some data needs to be encoded before being saved in the config file.
sub _encode {
    my $str = shift or return '';

    # colon and \n are config file delimiters, % is encoding scheme, \r is just ugly.
    $str =~ s/([%\r\n:])/sprintf("%%%02x",ord($1))/ge;
    return $str;
}

# Some data needs to be decoded before being handed to something external.
sub _decode {
    my $str = shift or return '';
    $str =~ s/%([\da-f]{2})/chr(hex($1))/ge;
    return $str;
}

=item * remove_team_user -- Deletes a team-user record in team configuration file.

    No warning.  No backup.  It is gone.  Team-user will no longer be able to login.
    Also removes any pending expires for team-user.
    Silently does nothing if team-user does not exist.

    ARGUMENTS
        team_user    (String) -- team user name

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if $team_user is empty.
        Fails if team configuration file is corrupt.
        Fails if cannot read or write to team configuration file.

    EXAMPLE
        my $results = $team_obj->remove_team_user($team_user);

=cut

sub remove_team_user {
    my ( $self, $team_user ) = @_;

    _validate_name($team_user);
    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);

    if ( !_check_team_user_exists( $team, $team_user ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    my $team_q_obj = Cpanel::Team::Queue->new();
    $team_q_obj->dequeue_task( $team->{owner}, $team_user ) or do {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'ProcessFailed', 'Unable to dequeue expire task for team user “[_1]”.', [$team_user] );
    };

    delete $team->{users}->{$team_user};
    @content = $self->_unparse_config($team);
    Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );
    $self->_safeclose_groupuser( $config_fh, $config_lock );
    my @sessions = _get_team_user_session( $self, $team_user );
    for my $active_session (@sessions) {
        Cpanel::Session::SinglePurge::purge_user( $active_session, 'remove team user' );
    }
    $self->_remove_team_user_dir($team_user);
    $self->_remove_2fa($team_user);

    return 1;
}

sub _remove_team_user_dir {
    my ( $self, $team_user ) = @_;

    # Removes the datastore, dynamicui & config cache files in team_user_dir.
    my $team_user_dir = ( Cpanel::PwCache::getpwnam( $self->{team_owner} ) )[7] . "/$team_user";

    Cpanel::AccessIds::do_as_user(
        $self->{team_owner},
        sub {
            require Cpanel::SafeDir::RM;
            Cpanel::SafeDir::RM::safermdir($team_user_dir);
            return;
        }
    );
    return;
}

=item * set_password -- Replaces current password for $team_user with $password.

    Expects a plain text password string.
    Encrypts the password string and saves it.
    If $team_user is suspended or expired this method will die and not change
    the password.

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.
        Fails if $team_user is suspended.
        Fails if $team_user has expired.

    EXAMPLE
        my $results = $team_obj->set_password( $team_user, $password );

=cut

sub set_password {
    my ( $self, $team_user, $password ) = @_;

    _validate_name($team_user);
    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);
    if ( !_check_team_user_exists( $team, $team_user ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }
    if ( $team->{users}->{$team_user}->{password} =~ /^!!/ ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'AccessDeniedToAccount', 'The account “[_1]” is suspended or expired. The system cannot set the password.', [$team_user] );
    }

    $team->{users}->{$team_user}->{password} = Cpanel::Auth::Generate::generate_password_hash($password);
    @content = $self->_unparse_config($team);
    Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );
    $self->_safeclose_groupuser( $config_fh, $config_lock );
    eval {
        my $result = Cpanel::AccessIds::do_as_user_with_exception(
            $self->{team_owner},
            sub {
                require Cpanel::API;
                my $mysql_user = $self->{team_owner} . '_' . $team_user;
                my $result     = Cpanel::API::execute(
                    'Mysql',
                    'set_password',
                    {
                        user     => $mysql_user,
                        password => $password
                    }
                );
                return $result;
            }
        );
    };
    if ( my $err = $@ ) {
        die Cpanel::Exception::create( 'AccessDeniedToAccount', 'The system cannot set the MySQL account password for “[_1]” due to the following error “[_2]”.', [ $team_user, $err ] );
    }

    return 1;
}

sub _lock_and_read {
    my $self = shift;

    my $config_fh;
    my $config_lock = Cpanel::SafeFile::safeopen( $config_fh, "<", $self->{config_file} );
    if ( !$config_lock ) {
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $self->{config_file}, mode => '<', error => $! ] );
    }
    local $!;    # <$config_fh> doesn't unset $! on success.
    my @config_lines;
    my $lines_read = chomp( @config_lines = <$config_fh> );
    if ( $! || !$lines_read ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'IO::FileReadError', [ path => $self->{config_file}, error => $! ] );
    }

    return $config_fh, $config_lock, @config_lines;
}

sub _check_team_user_exists {
    my ( $team, $team_user ) = @_;
    if ( !exists $team->{users}->{$team_user} ) {
        return 0;
    }
    return 1;
}

sub _check_domain_format {
    my $domain = shift;

    if ( !Cpanel::Validate::Domain::is_valid_cpanel_domain($domain) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid domain.', [$domain] );
    }

}

sub _get_domain_owner {
    my $domain = shift;

    my $domain_owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'default' => '' } );
    if ( !length $domain_owner ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'No users correspond to the domain “[_1]”.', [$domain] );
    }

    if ( !Cpanel::Validate::Username::user_exists($domain_owner) ) {    # This is very unlikely to ever fail.
        die Cpanel::Exception::create( 'InvalidParameter', 'The team owner “[_1]” does not exist.', [$domain_owner] );
    }

    return $domain_owner;
}

sub _check_primary_domain {
    my ( $team_owner, $domain ) = @_;
    if ( Cpanel::AcctUtils::Domain::getdomain($team_owner) ne $domain ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a primary domain.', [$domain] );
    }
    return;
}

sub _safeclose_groupuser {
    my ( $self, $config_fh, $config_lock ) = @_;

    my $close_ok       = Cpanel::SafeFile::safeclose( $config_fh, $config_lock );
    my ($team_owner)   = $self->{config_file} =~ m{([^/]+)$};
    my $team_owner_gid = ( Cpanel::PwCache::getpwnam($team_owner) )[3];
    Cpanel::Autodie::chown( 0, $team_owner_gid, $self->{config_file} ) if ( stat( $self->{config_file} ) )[5] != $team_owner_gid;

    return $close_ok;
}

sub _get_team_user_session {
    my ( $self, $team_user ) = @_;

    my @sessions          = ();
    my $session_cache_dir = "$Cpanel::Config::Session::SESSION_DIR/cache";
    my @candidates        = map { m{/([^/]+?):} } glob "$session_cache_dir/$team_user\@*";
    foreach my $candidate (@candidates) {
        my ( $username, $domain ) = split /@/, $candidate;
        my $domain_owner = _get_domain_owner($domain);
        if ( $self->{team_owner} eq $domain_owner ) {
            push @sessions, $candidate;
        }
    }
    return @sessions;
}

=item * add_roles -- Adds one or more roles to $team_user.

    If $team_user already has the role it silently does nothing.
    It does not replace roles.
    If you need to replace roles use set_roles() instead.
    Unlock team-user's mysql account when they are given database/admin roles.

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.
        Fails if $team_user had no roles, is being given a role, and the team is already at MAX_TEAM_USERS_WITH_ROLES.

    EXAMPLE
        my $results1 = $team_obj->add_roles( $team_user, 'email', 'web' );
        my $results2 = $team_obj->add_roles( $team_user, 'database' );

=cut

sub add_roles {
    my ( $self, $team_user, @roles ) = @_;

    _validate_name($team_user);
    if ( !@roles ) {
        return 1;    # Nothing to do.
    }
    _validate_roles(@roles);

    my $changed = 0;
    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);
    if ( !_check_team_user_exists( $team, $team_user ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    my %current_roles;
    @current_roles{ @{ $team->{users}->{$team_user}->{roles} } } = (1) x @{ $team->{users}->{$team_user}->{roles} };
    foreach my $role (@roles) {
        if ( !exists $current_roles{$role} ) {
            $current_roles{$role} = 1;
            $changed = 1;
        }
    }

    if ($changed) {

        # Check to see if this would go over the maximum number of team users with roles
        my $users_with_roles = grep { @{ $team->{users}{$_}{roles} } } keys %{ $team->{users} };
        if ( $users_with_roles >= max_team_users_with_roles_count( $team->{owner} ) ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Team already has “[_1]” team users with roles. This exceeds the maximum number of team users with roles if you add a role to team user “[_2]”.', [ $users_with_roles, $team_user ] );
        }

        @roles                                = sort keys %current_roles;
        $team->{users}->{$team_user}->{roles} = \@roles;
        @content                              = $self->_unparse_config($team);
        Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );

        # unlock the mysql team-user account
        my $mysql_user = $self->{team_owner} . "_" . $team_user;
        unsuspend_mysql_user($mysql_user) if grep { /^$Cpanel::Team::Constants::NEEDS_MYSQL$/ } @roles;

    }

    return $self->_safeclose_groupuser( $config_fh, $config_lock );
}

=item * remove_roles -- Removes one or more roles from $team_user.

    If $team_user does not have the role being removed it silently does nothing.
    Locks the mysql team-user account whenever database & admin roles are removed.

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.

    EXAMPLE
        my $results = $team_obj->remove_roles( $team_user, 'web', 'database' );

=cut

sub remove_roles {
    my ( $self, $team_user, @roles ) = @_;

    _validate_name($team_user);
    if ( !@roles ) {
        return 1;    # Nothing to do.
    }
    _validate_roles(@roles);

    my $changed = 0;
    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);
    if ( !_check_team_user_exists( $team, $team_user ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    my %current_roles;
    @current_roles{ @{ $team->{users}->{$team_user}->{roles} } } = (1) x @{ $team->{users}->{$team_user}->{roles} };
    foreach my $role (@roles) {
        if ( exists $current_roles{$role} ) {
            delete $current_roles{$role};
            $changed = 1;
        }    # Silently ignore deleting roles that are already gone.
    }

    # lock the mysql account for team-user whenever database/admin roles are removed
    if ( grep { /^$Cpanel::Team::Constants::NEEDS_MYSQL$/ } @roles ) {
        if ( !%current_roles || !grep { /^$Cpanel::Team::Constants::NEEDS_MYSQL$/ } ( keys %current_roles ) ) {
            my $mysql_user = $self->{team_owner} . "_" . $team_user;
            suspend_mysql_user($mysql_user);
        }
    }
    if ($changed) {
        @roles                                = sort keys %current_roles;
        $team->{users}->{$team_user}->{roles} = \@roles;
        @content                              = $self->_unparse_config($team);
        Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );
    }

    return $self->_safeclose_groupuser( $config_fh, $config_lock );
}

=item * set_roles -- Removes all current roles and replaces with role(s) passed in.

    Unlock team-user's mysql account when they are given database/admin roles
    Lock team-user's mysql account when they are stripped of database/admin roles.

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.

    EXAMPLE
        my $results = $team_obj->set_roles( $team_user, 'web', 'database' );

=cut

sub set_roles {
    my ( $self, $team_user, @roles ) = @_;

    _validate_name($team_user);
    _validate_roles(@roles);

    my $changed = 0;
    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);
    if ( !_check_team_user_exists( $team, $team_user ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    my %current_roles;
    @current_roles{ @{ $team->{users}->{$team_user}->{roles} } } = (1) x @{ $team->{users}->{$team_user}->{roles} };
    my $had_db_role = $current_roles{database} || $current_roles{admin};

    # Check to see if anything changed.
    if ( @roles == @{ $team->{users}->{$team_user}->{roles} } ) {    # Same number of elements
        foreach my $role (@roles) {
            if ( !exists $current_roles{$role} ) {
                $changed = 1;
            }
        }
    }
    else {
        $changed = 1;
    }
    if ($changed) {

        # Check to see if this would go over the maximum number of team users with roles.
        my $users_with_roles = grep { @{ $team->{users}{$_}{roles} } } keys %{ $team->{users} };
        if ( !keys %current_roles && @roles > 0 && $users_with_roles >= max_team_users_with_roles_count( $team->{owner} ) ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The Team already has “[_1]” team users with roles. This exceeds the maximum number of team users with roles if you add a role to team user “[_2]”.', [ $users_with_roles, $team_user ] );
        }

        @roles                                = sort @roles;
        $team->{users}->{$team_user}->{roles} = \@roles;
        @content                              = $self->_unparse_config($team);
        Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );
        my $mysql_user = $self->{team_owner} . "_" . $team_user;

        if ( grep { /^$Cpanel::Team::Constants::NEEDS_MYSQL$/ } @roles ) {
            unsuspend_mysql_user($mysql_user);    # Unlock team-user's mysql account
        }
        elsif ($had_db_role) {

            # roles modified from database/admin to something else
            suspend_mysql_user($mysql_user);
        }
        else {
            # do nothing when non database/admin roles gets switched.
        }
    }

    return $self->_safeclose_groupuser( $config_fh, $config_lock );
}

=item * set_notes -- Replaces current notes field with new notes.

    Replacing the notes field with an empty string is okay.

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.

    EXAMPLE
        my $results = $team_obj->set_notes( $team_user, 'George Washington is the first POTUS' );

=cut

sub set_notes {
    my ( $self, $team_user, $notes ) = @_;

    _validate_name($team_user);

    $notes //= '';
    if ( length $notes > $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The Notes field contains “[_1]” characters. The limit is “[_2]” characters.', [ length($notes), $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ] );
    }

    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);
    if ( !_check_team_user_exists( $team, $team_user ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    $team->{users}->{$team_user}->{notes} = $notes;
    @content = $self->_unparse_config($team);
    Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );
    return $self->_safeclose_groupuser( $config_fh, $config_lock );
}

=item * set_contact_email -- Replaces current contact_email & secondary_contact_email field for $team_user with $emails.

    Does some validation of emails in $emails to ensure it looks like a valid external email address.
    contact email address cannot be blank.
    secondary contact email address can be blank.

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.
        Fails if $email does not look like a valid external email address.

    EXAMPLE
        my $emails  = [ 'bob@mailinator.com' , 'jim@mailinator.com' ];
        my $results = $team_obj->set_contact_email( $team_user, $emails );

=cut

sub set_contact_email {
    my ( $self, $team_user, $emails ) = @_;

    _validate_name($team_user);
    foreach my $email ( @{$emails} ) {
        next if !$email;
        if ( !Cpanel::Validate::EmailRFC::is_valid_remote($email) ) {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid email address.', [$email] );
        }
    }

    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);
    if ( !_check_team_user_exists( $team, $team_user ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    # team user cannot empty their primary email
    if ( $emails->[0] && $team->{users}->{$team_user}->{contact_email} ne $emails->[0] ) {
        $team->{users}->{$team_user}->{contact_email} = $emails->[0];
    }

    # secondary contact email can be blank
    if ( defined $emails->[1] && $team->{users}->{$team_user}->{secondary_contact_email} ne $emails->[1] ) {
        $team->{users}->{$team_user}->{secondary_contact_email} = $emails->[1];
    }
    @content = $self->_unparse_config($team);
    Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );
    return $self->_safeclose_groupuser( $config_fh, $config_lock );
}

=item * get_mtime_team_config -- Provides modified timestamp for Team Config file.

    RETURNS: mtime for team-user; 0 otherwise.

    EXAMPLE
        my $team_cache_file_mtime = Cpanel::Team::Config::get_mtime_team_config( $team_user, $team_owner );

=cut

sub get_mtime_team_config {
    my ( $team_user, $team_owner ) = @_;
    return $team_user ? ( stat("$Cpanel::Team::Constants::TEAM_CONFIG_DIR/$team_owner") )[9] : 0;
}

sub _remove_2fa {
    my ( $self, $team_user ) = @_;
    my $tfa_obj = Cpanel::Security::Authn::TwoFactorAuth->new( { user => "$team_user\@$self->{team_owner}" } );
    if ( defined $tfa_obj && $tfa_obj->is_tfa_configured() ) {
        $tfa_obj->remove_tfa_userdata();
    }
    return;
}

=item * set_locale -- Replaces current locale field with new locale.

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if new locale is not valid on this system.
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.

    EXAMPLE
        my $results = $team_obj->set_locale( $team_user, 'es_es' ); # Iberian Spanish

=cut

sub set_locale {
    my ( $self, $team_user, $locale ) = @_;

    _validate_name($team_user);

    $locale = _validate_locale($locale);

    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);
    if ( !_check_team_user_exists( $team, $team_user ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    if ( $team->{users}->{$team_user}->{locale} ne $locale ) {
        $team->{users}->{$team_user}->{locale} = $locale;
        @content = $self->_unparse_config($team);
        Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );
    }

    return $self->_safeclose_groupuser( $config_fh, $config_lock );
}

sub _validate_locale {
    my $locale = shift;

    if ( !$locale || !Cpanel::Locale->get_handle()->cpanel_is_valid_locale($locale) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” does not refer to any of this system’s locales.', [$locale] );
    }
    return $locale;
}

=item * suspend_team_user

    Places current time in suspend field when team-users are suspended individually.
    Disables the password by placing '!!' characters at the beginning of the encrypted password string.
    Invalidates user's session token so if they attempt to perform any actions it takes them to the login screen.
    Locks the mysql team-user account preventing them from mysql access.
    If user is already suspended it silently does nothing.
    $reason is optional.

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.

    EXAMPLE
        my $results = $team_obj->suspend_team_user( team_user      => $team_user,
                                                    suspend_reason => $reason,  # optional field
           );
        my $results = $team_obj->suspend_team_user( team_user       => $team_user,
                                                    suspend_reason  => $reason, # optional field
                                                    suspend_as_team => 1,       # optional field
           );

=cut

sub suspend_team_user {
    my ( $self, %opts ) = @_;

    $opts{suspend_reason} //= '';

    _validate_name( $opts{team_user} );
    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);
    if ( !_check_team_user_exists( $team, $opts{team_user} ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [ $opts{team_user} ] );
    }

    if ( length $opts{suspend_reason} > $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The Suspend Reason field contains “[_1]” characters. The limit is “[_2]” characters.', [ length( $opts{suspend_reason} ), $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ] );
    }

    $team->{users}->{ $opts{team_user} }->{password} =~ s/^([^!])/!!$1/;    # Disable login and no extra '!!' on front.
    if ( !$team->{users}->{ $opts{team_user} }->{suspend_date} ) {
        if ( !$opts{suspend_as_team} ) {
            $team->{users}->{ $opts{team_user} }->{suspend_date}   = time;
            $team->{users}->{ $opts{team_user} }->{suspend_reason} = _encode( $opts{suspend_reason} );
        }
    }
    @content = $self->_unparse_config($team);
    Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );
    $self->_safeclose_groupuser( $config_fh, $config_lock );

    # lock the mysql account for team-user whenever team-user's account is suspended.
    my $mysql_user = $self->{team_owner} . "_" . $opts{team_user};
    suspend_mysql_user($mysql_user);

    my @sessions = _get_team_user_session( $self, $opts{team_user} );
    for my $active_session (@sessions) {
        Cpanel::Session::SinglePurge::purge_user( $active_session, 'suspend team user' );
    }
    return 1;
}

=item * _unsuspend_team_user

    Removes time stamp and reason from suspend field, replacing with empty string for users suspended individually.
    Removes '!!' from $team_user password irrespective of $unsuspend_for_team parameter.
    If team-user is not suspended it silently does nothing.

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.
        Fails if password is not disabled but has a suspend date.

    EXAMPLE
        my $results = $team_obj->unsuspend_team_user($team_user);
        my $results = $team_obj->unsuspend_team_user($team_user, 'unsuspend_as_team');

=cut

sub _unsuspend_team_user {
    my ( $self, $team_user, $unsuspend_for_team ) = @_;

    _validate_name($team_user);
    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);
    if ( !_check_team_user_exists( $team, $team_user ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    my $tu = $team->{users}->{$team_user};    # Simplifies the code below.
    if ( $tu->{password} !~ /^!!/ && $tu->{suspend_date} ) {
        die Cpanel::Exception::create( 'CorruptFile', 'Team configuration file “[_1]” is corrupt.', [ $self->{config_file} ] );
    }
    if ($unsuspend_for_team) {
        if ( !$tu->{suspend_date} ) {
            if ( !$tu->{expire_date} || ( $tu->{expire_date} && $tu->{expire_date} > $^T ) ) {
                $tu->{password} =~ s/^!!//;    # Enable login
            }
        }
    }
    elsif ( $tu->{suspend_date} ) {
        $tu->{suspend_date}   = '';
        $tu->{suspend_reason} = '';
        if ( !$tu->{expire_date} || ( $tu->{expire_date} && $tu->{expire_date} > $^T ) ) {
            $tu->{password} =~ s/^!!//;    # Enable login
        }
    }
    @content = $self->_unparse_config($team);
    Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );

    return $self->_safeclose_groupuser( $config_fh, $config_lock );
}

=item * suspend_team -- Suspends all of a team's team-users.

    Each team-user who is not currently suspended will get a '!!' inserted in
    front of their password, disabling their login.
    There is no need to insert a suspend timestamp because no one will see the
    team-users' accounts.  We only need to make sure they cannot login.
    Does not suspend the team owner.  This routine is called from the suspend
    cPanel user script.

    ERRORS
        All failures are fatal.
        Fails if team configuration file cannot be read or changed.

    EXAMPLE
        my $results = $team_obj->suspend_team();

=cut

sub suspend_team {
    my $self       = shift;
    my $team_users = $self->load()->{users};
    foreach my $team_user ( keys %{$team_users} ) {
        $self->suspend_team_user( team_user => $team_user, suspend_as_team => 1 );
    }
    return;
}

=item * unsuspend_team -- Unsuspends all of a team's team-users that were suspended by suspend_team().

    Each team-user who was not individually suspended will be unsuspended.
    Removes '!!' from their password (and thus login) re-enabled.
    No suspend timestamp needs to be cleared, because
    a team suspend does not use this field.
    Does not unsuspend the team owner.  This routine is called from the
    unsuspend cPanel user script.

    ERRORS
        All failures are fatal.
        Fails if team configuration file cannot be read or changed.

    EXAMPLE
        my $results = $team_obj->unsuspend_team();

=cut

sub unsuspend_team {
    my $self       = shift;
    my $team_users = $self->load()->{users};
    foreach my $team_user ( keys %{$team_users} ) {
        $self->_unsuspend_team_user( $team_user, 'unsuspend_as_team' );

        # scripts/unsuspendacct will unsuspend all team-user's MySQL account
        # including non-admin/database roles. Suspend team-user's MySQL account
        # with non-admin/database roles.
        my $mysql_user = $self->{team_owner} . '_' . $team_user;
        suspend_mysql_user($mysql_user) if $team_users->{$team_user}{suspend_date} || !grep { /^$Cpanel::Team::Constants::NEEDS_MYSQL$/ } @{ $team_users->{$team_user}{roles} };
    }
    return;
}

# Returns last login timestamp for $team_user under $team_owner in Unix Epoch time.
sub _get_lastlogin_time {
    my ( $team_owner, $team_user ) = @_;

    my $homedir = ( Cpanel::PwCache::getpwnam($team_owner) )[7];
    my $ll_file = "$homedir/$team_user/.lastlogin";
    if ( -e $ll_file ) {
        open my $fh, '<', $ll_file or die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $ll_file, mode => '<', error => $! ] );
        my @entries = <$fh>;
        close $fh;
        if ( $entries[-1] ) {
            my ( $ip, $timestamp ) = split / # /, $entries[-1];
            my $epoch = str2time($timestamp);
            $epoch = $epoch <= 0 ? '' : $epoch;    # Just in case something is not right.
            return $epoch;
        }
    }
    return '';
}

=item * remove_team -- Removes everything having to do with a team.

    Removes each team-user.
    Removes team configuration file.

    Everything should be deleted, including usernames and passwords.
    There is no undo.
    The cPanel team-owner account is not touched.

    Should *only* be called from Whostmgr::Accounts::Remove::Cleanup
    for race safety.

    ARGUMENTS
        <team-owner>   (String) -- cPanel account username.

    RETURNS: 1 for success.

    ERRORS
        All failures are fatal.
        Fails if $team_owner does not exist.
        Fails if team configuration file cannot be deleted because it doesn't
           exist or if the current user does not have permission to delete the
           file.

    EXAMPLE
        my $results = remove_team($team_owner);

=cut

sub remove_team {
    my ($team_owner) = shift;
    return 1 if !Cpanel::Autodie::exists("$Cpanel::Team::Constants::TEAM_CONFIG_DIR/$team_owner");

    my $team_obj = Cpanel::Team::Config->new($team_owner);
    my $team     = $team_obj->load();
    foreach my $team_user ( sort keys %{ $team->{users} } ) {
        $team_obj->remove_team_user($team_user);
    }

    my $succeeded = Cpanel::Autodie::unlink_if_exists("$team_obj->{config_file}");
    return $succeeded;
}

=item * set_expire

    Places $date and $reason in expire_date and expire_reason fields
    respectively in the team-user's configuration file record.
    Queues up expire task to execute at expire_date.

    If user has an expire task queued already, it replaces that task
    with a new one with a new expire date and new expire reason.

    If the new expire date is the same as the current task then it
    replaces the old reason with the new reason, even if the new reason
    is an empty string.  It does not re-queue the expire task.

    If user is already expired it silently does nothing.

    $date is Unix Epoch Time format.  It should be midnight team-owner
    local time, but we do not enforce this, nor should we.  This makes
    testing easier.  Besides we have no way to tell the team-user's
    time zone since this is only kept in the team-owner's browser.

    $reason is optional.

    RETURNS: 1 for success.

    ERRORS
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.
        Fails if an expire task cannot be created.
        Fails if expire date is in the past.
        Fails if expire date is too far in the future, after Sat Nov 20 17:46:39 2286 UTC.
        Fails if expire date is not in Unix Epoch format.

    EXAMPLE
        my $results = $team_obj->set_expire( $team_user, time + 60 * 60 * 24 * 90, "90 day contract" );
        my $results = $team_obj->set_expire( $team_user, $expire_date );

=cut

sub set_expire {
    my ( $self, $team_user, $date, $reason ) = @_;
    $reason //= '';

    _validate_name($team_user);

    my $now = time;
    if ( $date =~ /\D/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The expiration format should be Unix Epoch.' );
    }
    elsif ( $date < $now ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The expiration date is in the past.' );
    }
    elsif ( $date > 9_999_999_999 ) {    # This code will be wrong beginning Sat Nov 20 17:46:40 2286.;
        die Cpanel::Exception::create( 'InvalidParameter', 'The expiration date is too far in the future.' );
    }

    if ( length $reason > $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The Expire Reason field contains “[_1]” characters. The limit is “[_2]” characters.', [ length($reason), $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE ] );
    }

    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);
    if ( !_check_team_user_exists( $team, $team_user ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    if ( length $team->{users}->{$team_user}->{expire_date} && $team->{users}->{$team_user}->{expire_date} < $now && $team->{users}->{$team_user}->{password} =~ /^!!/ ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        return 1;    # Already expired.  Nothing to do.
    }

    # Just update reason.  No other change.
    if ( $team->{users}->{$team_user}->{expire_date} eq $date ) {
        $team->{users}->{$team_user}->{expire_reason} = $reason;
        @content = $self->_unparse_config($team);
        Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        return 1;
    }

    @{ $team->{users}->{$team_user} }{qw(expire_date expire_reason)} = ( $date, $reason );

    # We're replacing the expire task(s), if any.  Remove them all for this team-user..
    my $team_q_obj = Cpanel::Team::Queue->new();
    my @tasks      = $team_q_obj->find_tasks( $team->{owner}, $team_user );
    foreach my $task (@tasks) {
        $team_q_obj->dequeue_task($task)
          or do {
            $self->_safeclose_groupuser( $config_fh, $config_lock );
            die Cpanel::Exception::create( 'ProcessFailed', 'Unable to dequeue expire task for team user “[_1]”.', [$team_user] );
        }
    }

    my $expire_command = "/usr/local/cpanel/bin/expire_team_user $team->{owner} $team_user";
    $team_q_obj->queue_task( $date, $team->{owner}, $team_user, $expire_command )
      or do {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'ProcessFailed', 'Unable to queue expire task for team user “[_1]”.', [$team_user] );
      };

    @content = $self->_unparse_config($team);
    Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );
    $self->_safeclose_groupuser( $config_fh, $config_lock );

    return 1;
}

=item * expire_team_user

    Disables the password by placing '!!' characters at the beginning of
    the encrypted password string and will invalidate the team-user's
    session token so if they attempt to perform any actions it takes
    them to the login screen. Locks the mysql team-user account preventing
    them from mysql access.

    RETURNS: 1 for success.

    ERRORS
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.
        Fails if $team_user not already scheduled to expire unless $force
            is set to a true value.
        Fails if $team_user expire_date is an invalid value.
        Fails if $team_user expire_date is still in the future.

    EXAMPLE
        my $results = $team_obj->expire_team_user($team_user);
        my $results = $team_obj->expire_team_user($team_user, $force);

=cut

sub expire_team_user {
    my ( $self, $team_user, $force ) = @_;

    _validate_name($team_user);

    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);
    if ( !_check_team_user_exists( $team, $team_user ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    my $now = time;
    if ( !$force ) {
        if (  !exists $team->{users}->{$team_user}->{expire_date}
            || length $team->{users}->{$team_user}->{expire_date} != 10
            || $team->{users}->{$team_user}->{expire_date} =~ /\D/ ) {
            $self->_safeclose_groupuser( $config_fh, $config_lock );
            die Cpanel::Exception::create( 'InvalidParameter', 'Invalid expiration date “[_1]”.', [ $team->{users}->{$team_user}->{expire_date} ] );
        }
        elsif ( $team->{users}->{$team_user}->{expire_date} > $now ) {
            $self->_safeclose_groupuser( $config_fh, $config_lock );
            die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” is not scheduled to expire at this time.', [$team_user] );
        }
    }
    $team->{users}->{$team_user}->{expire_date} = $now;             # Actual time expire executed.
    $team->{users}->{$team_user}->{password} =~ s/^([^!])/!!$1/;    # Disable login and don't put extra '!!' on front.
    @content = $self->_unparse_config($team);
    Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );
    $self->_safeclose_groupuser( $config_fh, $config_lock );

    my @sessions = _get_team_user_session( $self, $team_user );
    for my $active_session (@sessions) {
        Cpanel::Session::SinglePurge::purge_user( $active_session, 'expire team user' );
    }

    # lock the mysql account for team-user whenever team-user's account is expired.
    my $mysql_user = $self->{team_owner} . "_" . $team_user;
    suspend_mysql_user($mysql_user);

    return 1;
}

=item * cancel_expire

    Removes expire task from queue (if there) and clears expire fields in
    the team config file.

    If team-user account has already expired, it un-expires it, meaning
    that it re-enables the password and removes any data in the expire
    fields.

    This does not un-suspend a team-user that is suspended.

    RETURNS: 1 for success.

    ERRORS
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.
        Fails if an expire task cannot be dequeued.
        Fails if $team_user password has not been disabled and has expire
            date older than 1 hour.
        Fails if $team_user has not expired and has no expire task in the
        queue.

    EXAMPLE
        my $results = $team_obj->cancel_expire($team_user);

=cut

sub cancel_expire {
    my ( $self, $team_user ) = @_;

    _validate_name($team_user);

    my ( $config_fh, $config_lock, @content ) = $self->_lock_and_read();
    my $team = $self->_parse_config(@content);
    if ( !_check_team_user_exists( $team, $team_user ) ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    my $team_q_obj = Cpanel::Team::Queue->new();
    my @tasks      = $team_q_obj->find_tasks( $team->{owner}, $team_user );
    if ( !@tasks && !$team->{users}->{$team_user}->{expire_date} ) {
        $self->_safeclose_groupuser( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'ProcessFailed', 'No expiration to cancel for team user “[_1]”.', [$team_user] );
    }
    foreach my $task (@tasks) {
        $team_q_obj->dequeue_task($task)
          or do {
            $self->_safeclose_groupuser( $config_fh, $config_lock );
            die Cpanel::Exception::create( 'ProcessFailed', 'Unable to dequeue expire task for team user “[_1]”.', [$team_user] );
          };
    }

    if ( $team->{users}->{$team_user}->{expire_date} ) {
        @{ $team->{users}->{$team_user} }{qw(expire_date expire_reason)} = ( '', '' );
        if (   !Cpanel::AcctUtils::Suspended::is_suspended( $team->{owner} )
            && !$team->{users}->{$team_user}->{suspend_date} ) {
            $team->{users}->{$team_user}->{password} =~ s/^!!//;    # Enable login
        }
    }
    @content = $self->_unparse_config($team);
    Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@content );
    $self->_safeclose_groupuser( $config_fh, $config_lock );

    return 1;
}

=item * reinstate_team_user

    Re-eables team-user account, undoing either an expire, or a suspend,
    or both. Unlocks the mysql team-user account. Does not remove a queued expire task.

    RETURNS: 1 for success.

    ERRORS
        Fails if cannot read or write to team configuration file.
        Fails if $team_user does not exist.
        Fails if $team-user has not expired or been suspended.

    EXAMPLE
        my $results = $team_obj->reinstate_team_user($team_user);

=cut

sub reinstate_team_user {
    my ( $self, $team_user ) = @_;

    _validate_name($team_user);
    my $team_user_info = $self->get_team_user($team_user);

    my $unsuspend_ok = 1;
    if ( $team_user_info->{suspend_date} ) {
        $unsuspend_ok = $self->_unsuspend_team_user($team_user);
    }

    my $unexpire_ok = 1;
    if ( $team_user_info->{expire_date} && $team_user_info->{expire_date} <= time ) {
        $unexpire_ok = $self->cancel_expire($team_user);
    }
    my $mysql_user = $self->{team_owner} . "_" . $team_user;
    unsuspend_mysql_user($mysql_user);

    return $unsuspend_ok && $unexpire_ok;
}

=item * suspend_mysql_user

    lock the mysql team-user account whenver a team-user is
     *  created with non database/admin roles
     *  suspended
     *  expired
     *  whenever database/admin roles are removed.

    RETURNS: 1 for success.

    EXAMPLE
        my $mysql_user = $team_owner . "_". $team_user;
        my $results    = Cpanel::Team::Config::suspend_mysql_user($mysql_user);

=cut

sub suspend_mysql_user {
    my ($mysql_user) = shift;

    # lock team-user's mysql account
    # need to run as root
    require Cpanel::MysqlUtils::Command;

    if ( Cpanel::MysqlUtils::Command::user_exists($mysql_user) ) {
        eval {
            require Cpanel::MysqlUtils::Suspension;

            #TODO : Currently suspend_mysql_users does not die on failures
            Cpanel::MysqlUtils::Suspension::suspend_mysql_users( $mysql_user, 1 );
        };
        if ( my $err = $@ ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'Unable to suspend MySQL account “[_1]” for the team user.', [$mysql_user] );
        }
    }
    return 1;
}

=item * unsuspend_mysql_user

    Unlock the mysql team-user account whenver a team-user is
    reinstated or given database/admin roles.

    RETURNS: 1 for success.

    EXAMPLE
        my $mysql_user = $team_owner . "_". $team_user;
        my $results    = Cpanel::Team::Config::unsuspend_mysql_user($mysql_user);

=back

=cut

sub unsuspend_mysql_user {
    my ($mysql_user) = shift;

    # Unlock team-user's mysql account
    # need to run as root
    require Cpanel::MysqlUtils::Command;
    if ( Cpanel::MysqlUtils::Command::user_exists($mysql_user) ) {
        eval {
            require Cpanel::MysqlUtils::Suspension;

            #TODO : Currently unsuspend_mysql_users does not die on failures
            Cpanel::MysqlUtils::Suspension::unsuspend_mysql_users( $mysql_user, 1 );
        };
        if ( my $err = $@ ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'Unable to unsuspend MySQL account “[_1]” for the team user.', [$mysql_user] );
        }
    }

    return 1;
}

1;
