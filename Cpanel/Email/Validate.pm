package Cpanel::Email::Validate;

# cpanel - Cpanel/Email/Validate.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

## no critic(RequireUseWarnings) -- no tests for this module

use Cpanel::ConfigFiles ();

sub valid_email {
    return if !$_[0];
    if (
        $_[0] =~ m{
            \A          # Beginning of scalar
            \w          # a word character
            [\w\-.+%]*   # 0 or more word characters, dashes, periods, or percent signs
            \@          # an at sign
            \w          # a word character
            [\w\-.]*     # 0 or more word characters, dashes, or periods
            \.          # A literal period
            [a-z]+      # 1 or more alphabet characters
            \z          # The End of a scalar
            }xsi
      ) {    # Case insensitive regex
        return 1;
    }
    return;
}

# HTML Encode all potentially dangerous characters
sub sanitize_email {
    $_[0] = substr( $_[0], 0, 1024 );
    $_[0] =~ s/\s//sg;
    $_[0] =~ s/</&lt;/sg;
    $_[0] =~ s/>/&gt;/sg;
    $_[0] =~ s/"/&quot;/sg;
    $_[0] =~ s/'/&apos;/sg;
    $_[0] =~ s/`/&acute;/sg;
    return $_[0];
}

# You have access to the mail group to use this validation function (or be root)
sub address_is_local {
    my $email = shift;
    my ( $user, $domain ) = split( /\@/, $email, 2 );

    # Detect system account
    if ( !$domain ) {
        return 1 if getpwnam($user);
        return 0;
    }

    if ( -e "$Cpanel::ConfigFiles::VALIASES_DIR/$domain" ) {
        if ( open my $vah_fh, '<', "$Cpanel::ConfigFiles::VALIASES_DIR/$domain" ) {
            while ( my $line = readline $vah_fh ) {
                if ( $line =~ m/^\Q$email\E: (.*)/ ) {
                    my $recp = $1;
                    if ( $recp !~ m/:fail:/ ) {
                        close $vah_fh;
                        return 1;
                    }
                }
                elsif ( $line =~ m/^\Q*\E: (.*)/ ) {
                    my $recp = $1;
                    if ( $recp !~ m/:(blackhole|fail):/ ) {
                        close $vah_fh;
                        return 1;
                    }
                }
            }
            close $vah_fh;
        }

        # A valiases file owned by root are not valid ???
        my $owner_uid = ( stat(_) )[4];
        return 0 if !$owner_uid;

        my $owner_homedir = ( getpwuid($owner_uid) )[7];
        if ( -e $owner_homedir . '/etc/' . $domain . '/passwd' ) {
            if ( open my $passwd_fh, '<', $owner_homedir . '/etc/' . $domain . '/passwd' ) {
                while ( my $line = readline $passwd_fh ) {
                    if ( $line =~ m/^\Q$user\E:/ ) {
                        close $passwd_fh;
                        return 1;
                    }
                }
                close $passwd_fh;
            }
        }
    }

    return 0;
}

1;
