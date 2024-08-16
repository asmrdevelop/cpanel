package Cpanel::MysqlUtils::MyCnf;

# cpanel - Cpanel/MysqlUtils/MyCnf.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Fcntl::Constants ();
use Cpanel::Debug            ();
use Cpanel::PwCache          ();
use Cpanel::ConfigFiles      ();

sub update_mycnf {    ## no critic(ProhibitExcessComplexity) -- needs significant refactoring
    my %args = @_;

    if ( !$args{'user'} ) {
        Cpanel::Debug::log_warn('Unable to update .my.cnf, invalid user');
        return;
    }

    my ( $uid, $gid, $homedir ) = ( Cpanel::PwCache::getpwnam( $args{'user'} ) )[ 2, 3, 7 ];
    if ( !$homedir || !-d $homedir ) {
        Cpanel::Debug::log_warn('Unable to update .my.cnf, invalid user, no home directory');
        return;
    }

    $args{'section'} ||= 'client';

    my $perms = 0600;
    my $mycnf = $homedir . '/.my.cnf';

    # We now only do this for root
    # We don't want to write a users password in plain text to their .my.cnf
    if ( $args{'user'} ne 'root' ) {

        # Case 95265, if they have a .my.cnf we will update it.
        return if ( exists $args{'mycnf'} );    # special where mycnf filename is sent in
        return if !-e $mycnf;
    }

    if ( $args{'mycnf'} ) {
        no warnings 'once';
        $mycnf = $args{'mycnf'};
        if ( $args{'mycnf'} eq $Cpanel::ConfigFiles::MYSQL_CNF ) {
            $perms = 0644;
        }
    }

    $perms = $args{'perms'} if defined $args{'perms'};

    unlink $mycnf if -l $mycnf;    # Remove a symlink

    if ( !-e $mycnf || -z _ ) {
        unlink $mycnf if -z _;     # Remove the empty file
        my $create_ok;
        {
            my $privs_obj;

            if ( $args{'user'} ne 'root' ) {
                require Cpanel::AccessIds::ReducedPrivileges;

                # Create as EUID
                $privs_obj = Cpanel::AccessIds::ReducedPrivileges->new( $uid, $gid );
            }
            $create_ok = create_mycnf( $mycnf, $args{'section'}, $args{'items'}, $perms );
        }
        if ( !$create_ok ) {
            Cpanel::Debug::log_warn("Failed to write .my.cnf for $args{'user'}");
            return;
        }
    }
    else {

        my $cnf_fh;
        my $user_sensitive_code = sub {
            chmod( $perms, $mycnf );
            sysopen( $cnf_fh, $mycnf, $Cpanel::Fcntl::Constants::O_RDWR | $Cpanel::Fcntl::Constants::O_NOFOLLOW );
        };

        if ( $args{'user'} eq 'root' ) {
            $user_sensitive_code->();
        }
        else {
            require Cpanel::AccessIds::ReducedPrivileges;
            Cpanel::AccessIds::ReducedPrivileges::call_as_user(
                $user_sensitive_code,
                $uid,
                $gid
            );
        }

        if ( defined fileno($cnf_fh) && fileno($cnf_fh) != -1 ) {
            my %settings_modified_in_this_section = ();
            my $in_section;
            my $has_section;

            # NB: This variable gets zeroed out down below to control flow.
            my $has_items = ( exists $args{'items'} && ref $args{'items'} eq 'ARRAY' ) ? 1 : 0;

            my @items;
            my @lines;
          LINE:
            while ( my $line = readline $cnf_fh ) {
                $line = _normalize_nl($line);
                if ($in_section) {

                    # Still in the section
                    if ( $line !~ m/^\s*\[/ ) {
                        if ( $line =~ m/^\s*([A-Za-z0-9-_.]+)\s*=(?:.*)$/i || $line =~ m/^\s*([A-Za-z0-9-_.]+)\s*/i ) {
                            my $setting = $1;

                            # case 81305 & 86401 Enforce that 'password' is used for password in ~/.my.cnf
                            $setting = 'password' if $setting eq 'pass';

                            # This can be true even if $has_items == 0 because
                            # $has_items might have been 1 initially.
                            if ( $settings_modified_in_this_section{$in_section}{$setting} ) {

                                # This means we have already modified the key
                                # in this section and this is a duplicate entry
                                # so we comment it it
                                push @lines, "#" . $line;
                                next LINE;
                            }

                            if ($has_items) {
                                my @unmatched;
                                foreach my $item ( @{ $args{'items'} } ) {
                                    foreach my $key ( sort keys %{$item} ) {
                                        my $normalized_key = _normalize_setting_key( $key, $setting );
                                        if ( _file_key($normalized_key) eq $setting ) {
                                            if ( my $line = _get_my_cnf_line_for( $normalized_key, $item->{$key} ) ) {
                                                push @lines, $line if !$args{'remove'};
                                                $settings_modified_in_this_section{$in_section}{$setting} = 1;
                                            }
                                            $setting = '';    # Indicate that the line was matched
                                        }
                                        else {

                                            # Save for later
                                            push @unmatched, { $key => $item->{$key} };
                                        }
                                    }
                                }

                                # If all items were matched, then we don't need to process and remaining items.
                                if ( !$setting && !@unmatched ) {
                                    $has_items = 0;
                                }

                                # If the item in .my.cnf wasn't matched, then conserve it
                                if ($setting) {
                                    push @lines, $line;
                                }

                                # Save remaining unmatched items
                                $args{'items'} = \@unmatched;
                                next LINE;
                            }
                        }
                        push @lines, $line;
                        next LINE;
                    }
                    else {
                        if ($has_items) {
                            foreach my $item ( @{ $args{'items'} } ) {
                                foreach my $key ( sort keys %{$item} ) {
                                    if ( my $line = _get_my_cnf_line_for( $key, $item->{$key} ) ) {
                                        $settings_modified_in_this_section{$in_section}{$key} = 1;
                                        push @lines, $line if !$args{'remove'};
                                    }
                                }
                            }
                            $has_items = 0;
                        }

                        $in_section = 0;    # Just left the section, line still needs to be processed below
                                            # to check what new section we are about to enter.
                    }
                }

                if ( $line =~ m/^\s*$/ || $line =~ m/^\s*#/ ) {
                    push @lines, $line;
                    next LINE;
                }
                elsif ( $line =~ m/^\s*\[\Q$args{'section'}\E\]/ ) {
                    $in_section = $has_section = $args{'section'};
                    push @lines, $line;
                    next LINE;
                }
                elsif ( $line =~ m/^\s*\[/ ) {
                    $in_section = 0;
                    push @lines, $line;
                    next LINE;
                }
                else {
                    push @lines, $line;
                }
            }
            if ( ( $has_items || @items ) && !$args{'if_present'} ) {
                if ( !$has_section ) {
                    push @lines, "[$args{'section'}]\n";
                }
                if ($has_items) {
                    foreach my $item ( @{ $args{'items'} } ) {
                        foreach my $key ( sort keys %{$item} ) {
                            if ( my $line = _get_my_cnf_line_for( $key, $item->{$key} ) ) {
                                $settings_modified_in_this_section{ $args{'section'} }{$key} = 1;
                                push @lines, $line;
                            }
                        }
                    }
                }
            }

            # Store results
            seek( $cnf_fh, 0, 0 );

            print {$cnf_fh} join( '', @lines );

            truncate( $cnf_fh, tell($cnf_fh) );

            close $cnf_fh;
        }
        else {
            Cpanel::Debug::log_warn("Failed to update $mycnf: $!");
            return;
        }
    }

    if ( $INC{'Cpanel/MysqlUtils/MyCnf/Basic.pm'} ) {
        Cpanel::MysqlUtils::MyCnf::Basic::clear_cache();
    }

    return 1;
}

# $items_args is an array of hash refs
sub create_mycnf {
    my ( $mycnf, $section, $items_args, $perms ) = @_;
    if ( !$perms ) {
        $perms = 0600;
    }
    my $orig_umask = umask 0000;
    if ( sysopen my $cnf_fh, $mycnf, $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_EXCL, $perms ) {
        print {$cnf_fh} "[$section]\n";
        if ( defined $items_args && ref $items_args eq 'ARRAY' ) {
            foreach my $item ( @{$items_args} ) {
                foreach my $key ( sort keys %{$item} ) {
                    if ( my $line = _get_my_cnf_line_for( $key, $item->{$key} ) ) {
                        print {$cnf_fh} $line;
                    }
                }
            }
        }
        close $cnf_fh;
        umask $orig_umask;
        return 1;
    }
    else {
        umask $orig_umask;
        return;
    }
}

sub _file_key {
    my $key = shift;
    return $key eq 'pass' ? 'password' : $key;
}

sub _does_line_key_match {
    my ( $existing_line, $key ) = @_;

    if ( !defined $existing_line ) {
        return 0;
    }

    if ( $existing_line =~ m/^(.*?)\s*=/ ) {
        my $mkey = $1;

        if ( $key eq $mkey ) { return 1; }
    }

    return 0;
}

sub _normalize_setting_key {
    my ( $key, $target ) = @_;

    # Normalize both the key and target key to use the same
    # space identifier when checking for equality. This will also
    # preserve the original space character.
    #
    # If the target contains the special character, we change the
    # matched key to use the same character. Settings can not have
    # both dashes and underscores.

    if ( index( $target, "-" ) >= 0 ) {
        $key =~ tr/_/-/;
    }
    elsif ( index( $target, "_" ) >= 0 ) {
        $key =~ tr/-/_/;
    }
    return $key;
}

sub _get_my_cnf_line_for {
    my ( $key, $value, $existing_line ) = @_;

    # Case 112061 - attempt to preserve existing formatting
    if ( _does_line_key_match( $existing_line, $key ) ) {

        # does this one have no value
        if ( defined $value && ( $value ne '' || $existing_line =~ m/=/ ) ) {
            my $qvalue = $value;

            if ( $existing_line =~ m/=\s*'/ ) {
                $qvalue = qq~'$qvalue'~;
            }
            elsif ( $existing_line =~ m/=\s*"/ ) {
                $qvalue = qq~"$qvalue"~;
            }
            elsif ( $qvalue =~ m/[\s]/ || $qvalue eq "" ) {
                $qvalue = qq~"$qvalue"~;
            }

            if ( $existing_line =~ s/^\s*[\w-]+\s*=\s*\K(['"]?.*?['"]?)(?=\s*(?:[#\n]))/$qvalue/ ) {
                return $existing_line;
            }
        }
    }

    my $file_key = _file_key($key);

    # A blank value is just a setting without parameters
    if ( !defined $value ) {
        return '';
    }
    elsif ( $value eq '' ) {
        return "$key\n";
    }
    elsif ( $value eq "''" || $value eq '""' ) {

        # handle the case where the value is a literal empty string.
        return "$key=$value\n";
    }
    elsif ( $value =~ tr/"// ) {
        return qq{$file_key='$value'\n} if $value !~ tr/'//;
        die "Can't serialize string with both double and single quotes";
    }
    elsif ( $value =~ m/[^A-Za-z0-9-_.]/ ) {

        # mysql read these values escaped or
        # unescaped no reason to do it here.
        return qq{$file_key="$value"\n};
    }
    else {
        return "$file_key=$value\n";
    }
}

# Ensure that every line read in has a terminating LF character (case 64008),
# and also strip out any CR characters that might have made it in.
sub _normalize_nl {
    my $line = shift;
    $line =~ s/\015?\012$//s;
    $line .= "\n";
    return $line;
}

1;
