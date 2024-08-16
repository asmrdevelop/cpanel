package Cpanel::Team::Config::Version;

# cpanel - Cpanel/Team/Config/Version.pm           Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use version;
use Cpanel::Locale::Utils::User ();
use Cpanel::Validate::Username  ();
use Cpanel::SafeFile            ();
use Cpanel::Team::Config        ();
use Cpanel::Team::Config::Fix   ();
use Cpanel::Team::Constants     ();

no strict 'refs';
no strict 'subs';

our %known_versions = (
    'v0.1' => 1,
    'v0.2' => 1,
    'v0.3' => 1,
    'v0.4' => 1,
    'v0.5' => 1,
    'v1.0' => 1,
    'v1.1' => 1,
);

my $team_name;

sub update {
    my ( $team_owner, $target_version, $opts ) = @_;

    if ( !Cpanel::Validate::Username::user_exists($team_owner) ) {
        print STDERR "No such team owner '$team_owner'.\n";
        return;
    }

    if ( !-e "$Cpanel::Team::Constants::TEAM_CONFIG_DIR/$team_owner" ) {
        print STDERR "$team_owner does not have a team configuration file to fix.\n";
        return;
    }
    my $owner_file = "$Cpanel::Team::Constants::TEAM_CONFIG_DIR/$team_owner";
    my ( $config_fh, $config_lock, @lines ) = _lock_and_read($owner_file);

    my $old_lines = join "\n", @lines, '';

    my ($file_version) = detect_version( $opts, @lines );
    if ( !defined $file_version ) {
        print STDERR "Unable to detect version.\n";
        Cpanel::SafeFile::safeclose( $config_fh, $config_lock );
        return;
    }
    ($team_name) = split /[ \n]+/, $lines[0];
    if ( $team_owner ne $team_name ) {

        # For some reason owner is wrong.  Fixing.
        $team_name = $team_owner;
    }

    # v1.0 is the first version that included a version number.
    $lines[0] = "$team_name" . ( version->parse($target_version) ge version->parse('v1.0') ? " $target_version\n" : "\n" );

    $file_version   =~ s/\./_/g;
    $target_version =~ s/\./_/g;

    my $team_user_cnt = 0;

    foreach ( @lines[ 1 .. $#lines ] ) {

        my $team_user;
        $team_user_cnt++;

        # Convert to internal version first.
        $team_user = &{ '_parse_entry_' . $file_version }($_);
        if ( !defined $team_user ) {
            my ($name) = split ':', $_, 2;
            if ( $opts->{remove} ) {
                splice( @lines, $team_user_cnt, 1 );
                $team_user_cnt--;
                print STDERR "Removing corrupt entry for team-user '$name'.\n" if $opts->{verbose};
                next;
            }
            else {
                print STDERR "Found corrupt team-user '$name', entry $team_user_cnt.  Cannot continue.\n";

                Cpanel::SafeFile::safeclose( $config_fh, $config_lock );
                return;
            }
        }

        $team_user = Cpanel::Team::Config::Fix::fix_team_user( $team_user, $opts ) if !$opts->{no_fix};
        if ( !defined $team_user ) {
            my ($name) = split ':', $_, 2;
            if ( $opts->{remove} ) {
                splice( @lines, $team_user_cnt, 1 );
                $team_user_cnt--;
                print STDERR "Removing corrupt entry for team-user '$name'.\n" if $opts->{verbose};
                next;
            }
        }

        # Convert to target version
        $_ = &{ '_unparse_entry_' . $target_version }($team_user);
    }

    my $new_lines = join '', @lines;

    # Save config
    if ( $new_lines ne $old_lines ) {    # Must have changed.
        Cpanel::SafeFile::Replace::safe_replace_content( $config_fh, $config_lock, \@lines ) if !$opts->{dry_run};
    }
    Cpanel::SafeFile::safeclose( $config_fh, $config_lock );

    return 1;
}

sub _parse_entry_v0_1 {

    # Team Configuration File v0.1:
    # <team-owner>
    # <team-user1>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>:<services>:<tfa>:<suspend>
    # <team-user2>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>:<services>:<tfa>:<suspend>
    #
    # Change from previous version:
    #     <notes> changed to "Percent Encoding" ':' -> '%3a', "\n" -> '%0a', "\r" -> '%0d', and '%' -> '%25'.

    my $entry = shift;

    my $delimiter_cnt = $entry =~ tr/://;
    if ( $delimiter_cnt != 8 ) {
        return undef;
    }
    my ( $team_user_name, $notes, $roles, $password, $creation, $contact, $services, $tfa, $suspend ) = split /:/, $entry, -1;
    my @roles = split /,/, $roles;
    $delimiter_cnt = $services =~ tr /,//;
    if ( $delimiter_cnt != 2 ) {
        print STDERR "Services field: '$services' is corrupt.  Ignoring services.\n";
        $services = ',,';
    }
    my ( $ftp, $webdisk, $email ) = split /,/, $services, -1;

    my $team_user = {
        team_user_name => $team_user_name,
        notes          => Cpanel::Team::Config::_decode($notes),
        roles          => [@roles],
        password       => $password,
        created        => $creation,
        contact_email  => $contact,
        services       => {
            ftp     => $ftp,
            webdisk => $webdisk,
            email   => $email,
        },
        tfa     => $tfa,
        suspend => $suspend,
    };

    return $team_user;
}

sub _parse_entry_v0_2 {

    # Team Configuration File v0.2:
    # <team-owner>
    # <team-user1>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>:<services>:<tfa>:<suspend-date>,<suspend-reason>
    # <team-user2>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>:<services>:<tfa>:<suspend-date>,<suspend-reason>
    #
    # Change from previous version:
    #     Split <suspend> field into date and reason.

    my $entry = shift;

    my $delimiter_cnt = $entry =~ tr/://;
    if ( $delimiter_cnt != 8 ) {
        return undef;
    }
    my ( $team_user_name, $notes, $roles, $password, $creation, $contact, $services, $tfa, $suspend ) = split /:/, $entry, -1;
    my @roles = split /,/, $roles;
    $delimiter_cnt = $services =~ tr /,//;
    if ( $delimiter_cnt != 2 ) {
        print STDERR "Services field: '$services' is corrupt.  Ignoring services.\n";
        $services = ',,';
    }
    my ( $ftp, $webdisk, $email ) = split /,/, $services, -1;
    my ( $suspend_date, $suspend_reason ) = ( ( split /,/, $suspend || ',', 2 ), '' );    # Ensure reason is never undef.

    my $team_user = {
        team_user_name => $team_user_name,
        notes          => Cpanel::Team::Config::_decode($notes),
        roles          => [@roles],
        password       => $password,
        created        => $creation,
        contact_email  => $contact,
        services       => {
            ftp     => $ftp,
            webdisk => $webdisk,
            email   => $email,
        },
        tfa            => $tfa,
        suspend_date   => $suspend_date,
        suspend_reason => $suspend_reason,
    };

    return $team_user;
}

sub _parse_entry_v0_3 {

    # Team Configuration File v0.3:
    # <team-owner>
    # <team-user1>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>,<secondary-contact-email>:<services>:<tfa>:<suspend-date>,<suspend-reason>
    # <team-user2>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>,<secondary-contact-email>:<services>:<tfa>:<suspend-date>,<suspend-reason>
    #
    # Change from previous version:
    #     Split <contact-email> field into <contact-email> and <secondary-contact-email>.
    my $entry = shift;

    my $delimiter_cnt = $entry =~ tr/://;
    if ( $delimiter_cnt != 8 ) {
        return undef;
    }
    my ( $team_user_name, $notes, $roles, $password, $creation, $contact, $services, $tfa, $suspend ) = split /:/, $entry, -1;
    my @roles = split /,/, $roles;
    $delimiter_cnt = $services =~ tr /,//;
    if ( $delimiter_cnt != 2 ) {
        print STDERR "Services field: '$services' is corrupt.  Ignoring services.\n";
        $services = ',,';
    }
    my ( $ftp,           $webdisk, $email ) = split /,/, $services, -1;
    my ( $contact_email, $secondary_contact_email ) = ( ( split /,/, $contact || ',', 2 ), '' );    # Ensure secondary_contact_email is never undef.
    my ( $suspend_date,  $suspend_reason )          = ( ( split /,/, $suspend || ',', 2 ), '' );    # Ensure reason is never undef.

    my $team_user = {
        team_user_name          => $team_user_name,
        notes                   => Cpanel::Team::Config::_decode($notes),
        roles                   => [@roles],
        password                => $password,
        created                 => $creation,
        contact_email           => $contact_email,
        secondary_contact_email => $secondary_contact_email,
        services                => {
            ftp     => $ftp,
            webdisk => $webdisk,
            email   => $email,
        },
        tfa            => $tfa,
        suspend_date   => $suspend_date,
        suspend_reason => Cpanel::Team::Config::_decode($suspend_reason),
    };

    return $team_user;
}

sub _parse_entry_v0_4 {

    # Team Configuration File v0.4:
    # <team-owner>
    # <team-user1>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>,<secondary-email>:<services>:<locale>:<suspend-date>,<suspend-reason>:<expire-date>,<expire-reason>
    # <team-user2>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>,<secondary-email>:<services>:<locale>:<suspend-date>,<suspend-reason>:<expire-date>,<expire-reason>
    #
    # Changes from previous version:
    #     Added field for <expire-date> and <expire-reason>.
    #     Changed <tfa> which was never needed to <locale>.
    my $entry = shift;

    my $delimiter_cnt = $entry =~ tr/://;
    if ( $delimiter_cnt == 8 ) {
        $entry .= ':,';
    }
    elsif ( $delimiter_cnt != 9 ) {
        print STDERR "Bad delimiter count for '$entry'!  Entry is corrupt.\n";
        return undef;
    }
    my ( $team_user_name, $notes, $roles, $password, $creation, $contact, $services, $locale, $suspend, $expire ) = split /:/, $entry, -1;
    my @roles = split /,/, $roles;
    $delimiter_cnt = $services =~ tr /,//;
    if ( $delimiter_cnt != 2 ) {
        print STDERR "Services field: '$services' is corrupt.  Ignoring services.\n";
        $services = ',,';
    }
    my ( $ftp,           $webdisk, $email ) = split /,/, $services, -1;
    my ( $contact_email, $secondary_contact_email ) = ( ( split /,/, $contact || ',', 2 ), '' );    # Ensure secondary_contact_email is never undef.
    my ( $suspend_date,  $suspend_reason )          = ( ( split /,/, $suspend || ',', 2 ), '' );    # Ensure reason is never undef.
    my ( $expire_date,   $expire_reason )           = ( ( split /,/, $expire  || ',', 2 ), '' );    # Ensure reason is never undef.
    $locale = '' if length $locale > 20;                                                            # Get rid of old 2FA test data that was never used.

    my $team_user = {
        team_user_name          => $team_user_name,
        notes                   => Cpanel::Team::Config::_decode($notes),
        roles                   => [@roles],
        password                => $password,
        created                 => $creation,
        contact_email           => $contact_email,
        secondary_contact_email => $secondary_contact_email,
        services                => {
            ftp     => $ftp,
            webdisk => $webdisk,
            email   => $email,
        },
        locale         => '',
        suspend_date   => $suspend_date,
        suspend_reason => Cpanel::Team::Config::_decode($suspend_reason),
        expire_date    => $expire_date,
        expire_reason  => Cpanel::Team::Config::_decode($expire_reason),
    };

    return $team_user;
}

sub _parse_entry_v0_5 {

    # Team Configuration File v0.5:
    # <team-owner>
    # <team-user1>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>,<secondary-contact-email>:<subacct-guid>:<locale>:<suspend-date>,<suspend-reason>:<expire-date>,<expire-reason>
    # <team-user2>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>,<secondary-contact-email>:<subacct-guid>:<locale>:<suspend-date>,<suspend-reason>:<expire-date>,<expire-reason>
    #
    # Change from previous version:
    #     Replace <services> with <subacct-guid>.

    my $entry = shift;

    my $delimiter_cnt = $entry =~ tr/://;
    if ( $delimiter_cnt == 8 ) {
        $entry .= ':,';
    }
    elsif ( $delimiter_cnt != 9 ) {
        print STDERR "Bad delimiter count for '$entry'!  Entry is corrupt.\n";
        return undef;
    }
    my ( $team_user_name, $notes, $roles, $password, $creation, $contact, $subacct_guid, $locale, $suspend, $expire ) = split /:/, $entry, -1;
    my @roles = split /,/, $roles;
    if ( length $subacct_guid ) {
        $delimiter_cnt = $subacct_guid =~ s/%3a/%3a/gi;
        if ( $delimiter_cnt != 3 ) {
            print STDERR "subacct-guid field: '$subacct_guid' is corrupt.  Ignoring subacct_guid.\n";
            $subacct_guid = '%3a%3a%3a';
        }
    }
    my ( $contact_email, $secondary_contact_email ) = ( ( split /,/, $contact || ',', 2 ), '' );    # Ensure secondary_contact_email is never undef.
    my ( $suspend_date,  $suspend_reason )          = ( ( split /,/, $suspend || ',', 2 ), '' );    # Ensure reason is never undef.
    my ( $expire_date,   $expire_reason )           = ( ( split /,/, $expire  || ',', 2 ), '' );    # Ensure reason is never undef.
    $locale = '' if length $locale > 20;                                                            # Get rid of old 2FA test data that was never used.

    my $team_user = {
        team_user_name          => $team_user_name,
        notes                   => Cpanel::Team::Config::_decode($notes),
        roles                   => [@roles],
        password                => $password,
        created                 => $creation,
        contact_email           => $contact_email,
        secondary_contact_email => $secondary_contact_email,
        subacct_guid            => Cpanel::Team::Config::_decode($subacct_guid),
        locale                  => '',
        suspend_date            => $suspend_date,
        suspend_reason          => Cpanel::Team::Config::_decode($suspend_reason),
        expire_date             => $expire_date,
        expire_reason           => Cpanel::Team::Config::_decode($expire_reason),
    };

    return $team_user;
}

sub _parse_entry_v1_0 {

    # Team Configuration File v1.0 (previously known as v0.6):
    # <team-owner> <version>
    # <team-user1>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>,<secondary-contact-email>:<subacct-guid>:<locale>:<suspend-date>,<suspend-reason>:<expire-date>,<expire-reason>
    # <team-user2>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>,<secondary-contact-email>:<subacct-guid>:<locale>:<suspend-date>,<suspend-reason>:<expire-date>,<expire-reason>
    #
    # Change from previous version:
    #     Version added to <team-owner> line.

    return _parse_entry_v0_5( $_[0] );
}

sub _parse_entry_v1_1 {

    # Team Configuration File v1.1:
    # <team-owner> <version>
    # <team-user1>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>,<secondary-contact-email>:<subacct-guid>:<locale>:<suspend-date>,<suspend-reason>:<expire-date>,<expire-reason>
    # <team-user2>:<notes>:<role1>,<role2>,...:<password>:<create-date>:<contact-email>,<secondary-contact-email>:<subacct-guid>:<locale>:<suspend-date>,<suspend-reason>:<expire-date>,<expire-reason>
    #
    # Change from previous version:
    #     Default locale for new team-user is team-owner's current locale.

    return _parse_entry_v0_5( $_[0] );
}

sub _unparse_entry_v0_1 {
    my $team_user = shift;

    $team_user->{notes}     = Cpanel::Team::Config::_encode( $team_user->{notes} );
    $team_user->{services}  = join ',', map { $_ // '' } @{ $team_user->{services} }{qw(ftp webdisk email)};
    $team_user->{roles}     = join ',', @{ $team_user->{roles} };
    $team_user->{suspended} = $team_user->{suspend_date} || $team_user->{suspend} || '';
    my $entry = join ':', map { $_ // '' } @{$team_user}{qw(team_user_name notes roles password created contact_email services tfa suspended)};
    return "$entry\n";
}

sub _unparse_entry_v0_2 {
    my $team_user = shift;

    $team_user->{notes}     = Cpanel::Team::Config::_encode( $team_user->{notes} );
    $team_user->{services}  = join ',', map { $_ // '' } @{ $team_user->{services} }{qw(ftp webdisk email)};
    $team_user->{roles}     = join ',', @{ $team_user->{roles} };
    $team_user->{suspended} = ( $team_user->{suspend_date} || $team_user->{suspend} || '' ) . ',' . Cpanel::Team::Config::_encode( $team_user->{suspend_reason} );
    my $entry = join ':', map { $_ // '' } @{$team_user}{qw(team_user_name notes roles password created contact_email services tfa suspended)};
    return "$entry\n";
}

sub _unparse_entry_v0_3 {
    my $team_user = shift;

    $team_user->{notes}         = Cpanel::Team::Config::_encode( $team_user->{notes} );
    $team_user->{services}      = join ',', map { $_ // '' } @{ $team_user->{services} }{qw(ftp webdisk email)};
    $team_user->{roles}         = join ',', @{ $team_user->{roles} };
    $team_user->{contact_email} = join ',', map { $_ // '' } @{$team_user}{qw(contact_email secondary_contact_email)};
    $team_user->{suspended}     = ( $team_user->{suspend_date} || $team_user->{suspend} || '' ) . ',' . Cpanel::Team::Config::_encode( $team_user->{suspend_reason} );
    my $entry = join ':', map { $_ // '' } @{$team_user}{qw(team_user_name notes roles password created contact_email services tfa suspended)};
    return "$entry\n";
}

sub _unparse_entry_v0_4 {
    my $team_user = shift;

    $team_user->{notes}         = Cpanel::Team::Config::_encode( $team_user->{notes} );
    $team_user->{services}      = join ',', map { $_ // '' } @{ $team_user->{services} }{qw(ftp webdisk email)};
    $team_user->{roles}         = join ',', @{ $team_user->{roles} };
    $team_user->{contact_email} = join ',', map { $_ // '' } @{$team_user}{qw(contact_email secondary_contact_email)};
    $team_user->{locale}        = '';
    $team_user->{suspended}     = ( $team_user->{suspend_date} || $team_user->{suspend} || '' ) . ',' . Cpanel::Team::Config::_encode( $team_user->{suspend_reason} );
    $team_user->{expire}        = ( $team_user->{expire_date}  || $team_user->{expire}  || '' ) . ',' . Cpanel::Team::Config::_encode( $team_user->{expire_reason} );
    my $entry = join ':', map { $_ // '' } @{$team_user}{qw(team_user_name notes roles password created contact_email services locale suspended expire)};
    return "$entry\n";
}

sub _unparse_entry_v0_5 {
    my $team_user = shift;

    $team_user->{notes}         = Cpanel::Team::Config::_encode( $team_user->{notes} );
    $team_user->{roles}         = join ',', @{ $team_user->{roles} };
    $team_user->{contact_email} = join ',', map { $_ // '' } @{$team_user}{qw(contact_email secondary_contact_email)};
    $team_user->{subacct_guid}  = Cpanel::Team::Config::_encode( $team_user->{subacct_guid} ) // '';
    $team_user->{locale}        = '';
    $team_user->{suspended}     = ( $team_user->{suspend_date} || $team_user->{suspend} || '' ) . ',' . Cpanel::Team::Config::_encode( $team_user->{suspend_reason} );
    $team_user->{expire}        = ( $team_user->{expire_date}  || $team_user->{expire}  || '' ) . ',' . Cpanel::Team::Config::_encode( $team_user->{expire_reason} );
    my $entry = join ':', map { $_ // '' } @{$team_user}{qw(team_user_name notes roles password created contact_email subacct_guid locale suspended expire)};
    return "$entry\n";
}

sub _unparse_entry_v1_0 {
    return _unparse_entry_v0_5(shift);
}

sub _unparse_entry_v1_1 {
    my $team_user = shift;

    $team_user->{notes}         = Cpanel::Team::Config::_encode( $team_user->{notes} );
    $team_user->{roles}         = join ',', @{ $team_user->{roles} };
    $team_user->{contact_email} = join ',', map { $_ // '' } @{$team_user}{qw(contact_email secondary_contact_email)};
    $team_user->{subacct_guid}  = Cpanel::Team::Config::_encode( $team_user->{subacct_guid} ) // '';
    if ( !length $team_user->{locale} ) {
        $team_user->{locale} = Cpanel::Locale::Utils::User::get_user_locale($team_name) // 'en';
    }
    $team_user->{suspended} = ( $team_user->{suspend_date} || $team_user->{suspend} || '' ) . ',' . Cpanel::Team::Config::_encode( $team_user->{suspend_reason} );
    $team_user->{expire}    = ( $team_user->{expire_date}  || $team_user->{expire}  || '' ) . ',' . Cpanel::Team::Config::_encode( $team_user->{expire_reason} );
    my $entry = join ':', map { $_ // '' } @{$team_user}{qw(team_user_name notes roles password created contact_email subacct_guid locale suspended expire)};
    return "$entry\n";
}

sub detect_version {
    my ( $opts, @lines ) = @_;

    my ($file_version) = ( split /[ \n]+/, $lines[0] )[1];
    if ( defined $file_version && $file_version =~ /^v(?:\d+)(?:\.(?:\d+))+$/ ) {
        return $file_version;    # This should detect v1.0+
    }

    my %found_vers = ();
    @found_vers{ keys %known_versions } = (0) x scalar keys %known_versions;
    my $already_found_pre_v0_4  = 0;
    my $already_found_post_v0_3 = 0;
    foreach my $entry ( @lines[ 1 .. $#lines ] ) {
        my $field_cnt = $entry =~ tr/://;
        if ( $field_cnt == 8 ) {

            if ($already_found_post_v0_3) {
                print STDERR "Team Configuration file is corrupt.  Cannot detect version.\n";
                return undef;
            }

            # Must be v0.1-v0.3
            my ( $notes, $contact_email, $suspend ) = ( split /:/, $entry, -1 )[ 1, 5, 8 ];
            $suspend       =~ /,/ and do { $found_vers{v0.2}++; };
            $contact_email =~ /,/ and do { $found_vers{v0.3}++; };
            $already_found_pre_v0_4 = 1;
        }
        elsif ( $field_cnt == 9 ) {

            if ($already_found_pre_v0_4) {
                print STDERR "Team Configuration file is corrupt.  Cannot detect version.\n";
                return;
            }

            # Must be v0.4-v0.5
            my ( $contact_email, $services_or_subacct_guid ) = ( split /:/, $entry, -1 )[ 5, 6 ];
            if ( length $services_or_subacct_guid == 0 || $services_or_subacct_guid =~ /(?:%3a.*){3}/i ) {
                $found_vers{v0.5}++;    # Must be subacct_guid
            }
            elsif ( $services_or_subacct_guid =~ /(?:,.*){2}/ ) {
                $found_vers{v0.4}++;    # Must be services
            }
            else {
                print STDERR "Team Configuration file is corrupt.  Services/Subacct_guid field is ambiguous.  Cannot detect version.\n";
                return;
            }
            $already_found_post_v0_3 = 1;
        }
        else {
            print STDERR "Team configuration file is corrupt.  Cannot detect version.\n";
            return if !$opts->{remove};
        }
    }
    if ($already_found_pre_v0_4) {
        return 'v0.3' if $found_vers{v0.3};
        return 'v0.2' if $found_vers{v0.2};
        return 'v0.1';
    }
    elsif ($already_found_post_v0_3) {
        return 'v0.5' if $found_vers{v0.5};
        return 'v0.4';
    }
    else {
        # No entries.  Could be any version.
        return $Cpanel::Team::Constants::LATEST_CONFIG_VERSION;
    }
}

sub _lock_and_read {
    my $owner_file = shift;

    my $config_fh;
    my $config_lock = Cpanel::SafeFile::safeopen( $config_fh, "<", $owner_file );
    if ( !$config_lock ) {
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $owner_file, mode => '<', error => $! ] );
    }
    local $!;    # <$config_fh> doesn't unset $! on success.
    my @config_lines;
    my $lines_read = chomp( @config_lines = <$config_fh> );
    if ( $! || !$lines_read ) {
        Cpanel::SafeFile::safeclose( $config_fh, $config_lock );
        die Cpanel::Exception::create( 'IO::FileReadError', [ path => $owner_file, error => $! ] );
    }

    return $config_fh, $config_lock, @config_lines;
}

1;
