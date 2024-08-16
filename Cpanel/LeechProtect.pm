package Cpanel::LeechProtect;

# cpanel - Cpanel/LeechProtect.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Carp                                  ();
use Cpanel                                ();
use Cpanel::Htaccess                      ();
use Cpanel::Locale                        ();
use Cpanel::Logger                        ();
use Cpanel::Encoder::Tiny                 ();
use Cpanel::Encoder::URI                  ();
use Cpanel::FileUtils::TouchFile          ();
use Cpanel::Rand::Get                     ();
use Cpanel::Server::Type::Role::WebServer ();
use File::Spec                            ();
use Cpanel::Imports;

our $VERSION = '1.2';

my $backtrace      = 1;
my $user_conf_file = '.leechprotect-conf';

sub LeechProtect_init { }

sub LeechProtect_setup { goto &setup; }

sub setup {
    my $result = _setup(@_);
    if ( defined $result ) {
        my ( $dir, $item, $type ) = @_;

        if ( $type ne 'html' ) {
            print Cpanel::Encoder::Tiny::safe_html_encode_str($result);
        }
        else {
            print $result;
        }
    }
    return;
}

sub api2_setup {
    my %opts   = @_;
    my $result = _setup( $opts{dir}, $opts{item}, $opts{type} );
    return $result;
}

sub _setup {
    my ( $dir, $item, $type ) = @_;

    my $dir_meta = Cpanel::Htaccess::_htaccess_dir_setup($dir);
    if ( !$dir_meta ) {
        die locale()->maketext("Invalid directory.") . "\n";
    }

    my $path = "$dir_meta->{'dir'}/$user_conf_file";

    if ( open my $conf_fh, '<', $path ) {
        while ( my $line = readline $conf_fh ) {
            chomp $line;
            my ( $key, $value ) = split( /\s*=\s*/, $line, 2 );
            next if !$key;
            if ( $key eq $item ) {
                if ( $type eq 'checkbox' || $type eq 'check' ) {
                    if ($value) {
                        return 'checked';
                    }
                }
                elsif ( $type eq 'url' ) {
                    return Cpanel::Encoder::URI::uri_encode_str($value);
                }
                elsif ( $type eq 'html' ) {
                    return Cpanel::Encoder::Tiny::safe_html_encode_str($value);
                }
                elsif ( $type eq 'raw' ) {
                    return $value;
                }
                else {
                    die locale()->maketext( "Invalid type “[_1]”.", $type ) . "\n";
                }
            }
        }
        close $conf_fh;
        return undef;    #We couldn't find the key requested
    }
    else {
        if ( not $!{ENOENT} ) {    # If the file exists but we can't read it
            my $error = "$!";      #Required to pass to make text since locale() overwrites it!!
            die locale()->maketext( "LeechProtect configuration exists but we can’t access it: [_1]", $error ) . "\n";
        }
        return undef;
    }
}

sub LeechProtect_status { goto &status; }

sub status {
    my $dir = shift;

    my $dir_meta = Cpanel::Htaccess::_htaccess_dir_setup($dir);
    if ( !$dir_meta ) {
        $Cpanel::CPERROR{'leechprotect'} = 'Invalid directory';
        return;
    }

    if ( !-e $dir_meta->{'dir'} . '/.htaccess' ) {
        print 'disabled';
        return;
    }

    if ( open my $ht_fh, '<', $dir_meta->{'dir'} . '/.htaccess' ) {
        while ( my $line = readline $ht_fh ) {
            if ( $line =~ m/^\s*RewriteCond\s+\$\{LeechProtect/ ) {
                print 'enabled';
                close $ht_fh;
                return;
            }
        }
        close $ht_fh;
    }
    else {
        Cpanel::Logger::logger(
            {
                'message'   => "Failed to read LeechProtect configuration $dir_meta->{'dir'}/.htaccess: $!",
                'level'     => 'warn',
                'service'   => __PACKAGE__,
                'output'    => 0,
                'backtrace' => $backtrace,
            }
        );
        $Cpanel::CPERROR{'leechprotect'} = 'Failed to read LeechProtect configuration';
        return;
    }
    print 'disabled';
    return;
}

sub LeechProtect_enable { goto &enable; }

sub enable {
    my ( $dir, $numhits, $badurl, $email, $killcompro ) = @_;

    if ( !main::hasfeature('cpanelpro_leechprotect') || !main::hasfeature('leechprotect') ) {
        $Cpanel::CPERROR{'leechprotect'} = 'Sorry this feature is not enabled';
        print 'Sorry this feature is not enabled';
        return wantarray ? ( 0, 'Sorry this feature is not enabled' ) : 0;
    }
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        $Cpanel::CPERROR{'leechprotect'} = 'Sorry, this feature is disabled in demo mode.';
        print "Sorry, this feature is disabled in demo mode.";
        return wantarray ? ( 0, "Sorry, this feature is disabled in demo mode." ) : 0;
    }

    $numhits = int $numhits;
    if ( $numhits < 1 ) { $numhits = 4; }

    my $dir_meta = Cpanel::Htaccess::_htaccess_dir_setup($dir);
    if ( !$dir_meta ) {
        $Cpanel::CPERROR{'leechprotect'} = 'Invalid directory';
        return;
    }

    my ( $conf_status, $conf_message ) = _update_conf(
        {
            'dir'     => $dir_meta->{'dir'},
            'email'   => $email,
            'kill'    => $killcompro,
            'url'     => $badurl,
            'numhits' => $numhits,
        }
    );
    if ($conf_status) {
        my ( $ht_status, $ht_message ) = _update_htaccess(
            {
                'dir'     => $dir_meta->{'dir'},
                'enable'  => 1,
                'url'     => $badurl,
                'numhits' => $numhits,
            }
        );
        if ($ht_status) {
            return wantarray ? ( 1, "LeechProtection enabled for $dir_meta->{'dir'}" ) : 1;
        }
        else {    # Failed to update htaccess
            $Cpanel::CPERROR{'leechprotect'} = $ht_message;
            return;
        }
    }
    else {        # Failed to update configuration
        $Cpanel::CPERROR{'leechprotect'} = $conf_message;
        return;
    }
}

sub LeechProtect_disable { goto &disable; }

sub disable {
    my $dir = shift;

    if ( !main::hasfeature('cpanelpro_leechprotect') || !main::hasfeature('leechprotect') ) {
        $Cpanel::CPERROR{'leechprotect'} = 'Sorry this feature is not enabled';
        print 'Sorry this feature is not enabled';
        return wantarray ? ( 0, 'Sorry this feature is not enabled' ) : 0;
    }
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        $Cpanel::CPERROR{'leechprotect'} = 'Sorry, this feature is disabled in demo mode.';
        print "Sorry, this feature is disabled in demo mode.";
        return wantarray ? ( 0, "Sorry, this feature is disabled in demo mode." ) : 0;
    }

    my $dir_meta = Cpanel::Htaccess::_htaccess_dir_setup($dir);
    if ( !$dir_meta ) {
        return wantarray ? ( 0, 'Invalid directory' ) : 0;
    }

    my ( $ht_status, $ht_message ) = _update_htaccess(
        {
            'dir'    => $dir_meta->{'dir'},
            'enable' => 0,
        }
    );

    if ($ht_status) {
        return wantarray ? ( 1, "LeechProtection disabled for $dir_meta->{'dir'}" ) : 1;
    }
    else {
        return wantarray ? ( 0, $ht_message ) : 0;
    }
}

sub LeechProtect__update_conf {
    return if !Cpanel::Server::Type::Role::WebServer->is_enabled();
    goto &_update_conf;
}

sub _update_conf {
    my $args_ref = shift;

    if ( !main::hasfeature('cpanelpro_leechprotect') || !main::hasfeature('leechprotect') ) {
        $Cpanel::CPERROR{'leechprotect'} = 'Sorry this feature is not enabled';
        print 'Sorry this feature is not enabled';
        return wantarray ? ( 0, 'Sorry this feature is not enabled' ) : 0;
    }
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        $Cpanel::CPERROR{'leechprotect'} = 'Sorry, this feature is disabled in demo mode.';
        print "Sorry, this feature is disabled in demo mode.";
        return wantarray ? ( 0, "Sorry, this feature is disabled in demo mode." ) : 0;
    }

    if ( !$args_ref->{'dir'} || !-d $args_ref->{'dir'} ) {
        return wantarray ? ( 0, 'Invalid directory' ) : 0;
    }

    my $conf_file = $args_ref->{'dir'} . '/' . $user_conf_file;
    Cpanel::FileUtils::TouchFile::touchfile($conf_file);

    open( my $conf_fh, '+<', $conf_file ) or do {
        Cpanel::Logger::logger(
            {
                'message'   => "Failed to read LeechProtect configuration $conf_file: $!",
                'level'     => 'warn',
                'service'   => __PACKAGE__,
                'output'    => 0,
                'backtrace' => $backtrace,
            }
        );
        return wantarray ? ( 0, "Failed to read LeechProtect configuration $conf_file" ) : 0;
    };

    my %old_conf;

    # Fetch existing values
    while ( my $line = readline $conf_fh ) {
        chomp $line;
        my ( $key, $value ) = split( /\s*=\s*/, $line, 2 );
        if ($key) {
            $old_conf{$key} = $value;
        }
    }
    seek( $conf_fh, 0, 0 );

    # Update values
    foreach my $key ( keys %{$args_ref} ) {
        next if ( !$key || $key eq 'dir' );
        $old_conf{$key} = $args_ref->{$key};
    }

    # Write new values
    foreach my $key ( sort keys %old_conf ) {
        next if !$old_conf{$key};    # Remove lines
        print {$conf_fh} $key . '=' . $old_conf{$key} . "\n";
    }
    truncate( $conf_fh, tell($conf_fh) );
    close $conf_fh;

    return 1;
}

sub LeechProtect__update_htaccess { goto &_update_htaccess; }

sub _update_htaccess {
    my $args_ref = shift;

    if ( !main::hasfeature('cpanelpro_leechprotect') || !main::hasfeature('leechprotect') ) {
        $Cpanel::CPERROR{'leechprotect'} = 'Sorry this feature is not enabled';
        print 'Sorry this feature is not enabled';
        return wantarray ? ( 0, 'Sorry this feature is not enabled' ) : 0;
    }
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        $Cpanel::CPERROR{'leechprotect'} = 'Sorry, this feature is disabled in demo mode.';
        print "Sorry, this feature is disabled in demo mode.";
        return wantarray ? ( 0, "Sorry, this feature is disabled in demo mode." ) : 0;
    }

    if ( !$args_ref->{'dir'} || !-d $args_ref->{'dir'} ) {
        return wantarray ? ( 0, 'Invalid directory' ) : 0;
    }

    my $token = Cpanel::Rand::Get::getranddata( 32, [ 'A' .. 'Z', 'a' .. 'z', '0' .. '9' ] );

    my $ht_file = $args_ref->{'dir'} . '/.htaccess';

    if ( -e $ht_file ) {    # Update
        if ( open my $ht_fh, '+<', $ht_file ) {
            my @htaccess;

            if ( $args_ref->{'enable'} ) {
                my $num_hits = $args_ref->{'numhits'} && $args_ref->{'numhits'} =~ m/^\d+$/ ? $args_ref->{'numhits'} : 4;
                my $bad_url  = $args_ref->{'url'}                                           ? $args_ref->{'url'}     : '/';

                # Stick all rules at top of htaccess file
                push @htaccess, "RewriteEngine on\n", 'RewriteCond ${LeechProtect:' . $args_ref->{'dir'} . ':%{REMOTE_USER}:%{REMOTE_ADDR}:' . $num_hits . ':' . $token . "} leech\n", 'RewriteRule .* ' . $bad_url . "\n";
            }

            # Strip out all old LeechProtection lines
            my $has_leech = 0;
            while ( my $line = readline $ht_fh ) {
                next if $line =~ m/^\s*$/;                                            # Remove blank lines
                next if $line =~ m/^\s*RewriteEngine\s+/ && $args_ref->{'enable'};    # Only remove if enabled (used for redirects as well)
                if ( $line =~ m/^\s*RewriteCond\s+\$\{LeechProtect/ ) {
                    $has_leech = 1;
                    next;
                }
                if ($has_leech) {                                                     # Try to match next LeechProtection rewrite
                    $has_leech = 0;
                    if ( $line =~ m/^\s*RewriteRule\s+\.\*\s+/ ) {
                        next;
                    }
                }
                push @htaccess, $line;
            }
            seek( $ht_fh, 0, 0 );
            print {$ht_fh} join( '', @htaccess );
            truncate( $ht_fh, tell($ht_fh) );
            close $ht_fh;
            return wantarray ? ( 1, "Updated $ht_file" ) : 1;
        }
        else {
            Cpanel::Logger::logger(
                {
                    'message'   => "Failed to read LeechProtect configuration $ht_file: $!",
                    'level'     => 'warn',
                    'service'   => __PACKAGE__,
                    'output'    => 0,
                    'backtrace' => $backtrace,
                }
            );
            return wantarray ? ( 0, "Failed to read $ht_file" ) : 0;
        }
    }
    elsif ( $args_ref->{'enable'} ) {
        if ( open my $ht_fh, '>', $ht_file ) {
            my $num_hits = $args_ref->{'numhits'} && $args_ref->{'numhits'} =~ m/^\d+$/ ? $args_ref->{'numhits'} : 4;
            my $bad_url  = $args_ref->{'url'}                                           ? $args_ref->{'url'}     : '/';
            print {$ht_fh} "RewriteEngine on\n";
            print {$ht_fh} 'RewriteCond ${LeechProtect:' . $args_ref->{'dir'} . ':%{REMOTE_USER}:%{REMOTE_ADDR}:' . $num_hits . ':' . $token . "} leech\n";
            print {$ht_fh} 'RewriteRule .* ' . $bad_url . "\n";
            close $ht_fh;
        }
        else {
            return wantarray ? ( 0, "Failed to create $ht_file: $!" ) : 0;
        }
    }
    else {    # No need to update
        return wantarray ? ( 1, 'Updated successfully' ) : 1;
    }
}

sub LeechProtect_showpasswdfile { goto &showpasswdfile; }

sub showpasswdfile {
    my ($dir) = @_;
    my $locale = Cpanel::Locale->get_handle();

    my $dir_meta = Cpanel::Htaccess::_htaccess_dir_setup($dir);
    if ( !$dir_meta ) {
        $Cpanel::CPERROR{'leechprotect'} = 'Invalid directory';
        return;
    }

    my $tdir = $dir_meta->{'tdir'};
    $tdir =~ s/$Cpanel::homedir//;    # If you pass /home/foo/etc you get 'etc' back but
                                      # if you pass /home/foo you get '/home/foo' back. Cool.

    my $protected_dir = File::Spec->canonpath("$Cpanel::homedir/$tdir");
    if ( !-e $protected_dir ) {
        $Cpanel::CPERROR{'leechprotect'} = $locale->maketext( 'Internal error: can’t find that folder: [_1]', $protected_dir );
        return;
    }

    return Cpanel::Encoder::Tiny::safe_html_encode_str("$Cpanel::homedir/.htpasswds/$dir_meta->{'tdir'}/passwd");
}

sub LeechProtect_getrealpasswdfile { goto &getrealpasswdfile; }

sub getrealpasswdfile {
    my ($dir) = @_;

    my $dir_meta = Cpanel::Htaccess::_htaccess_dir_setup($dir);
    if ( !$dir_meta ) {
        $Cpanel::CPERROR{'leechprotect'} = 'Invalid directory';
        return;
    }

    my $passwdfile = '';
    if ( open my $ht_fh, '<', $dir_meta->{'dir'} . '/.htaccess' ) {
        while ( my $line = readline $ht_fh ) {
            if ( $line =~ m/^\s*AuthUserFile\s+\"?([^\"]+)\"?/ ) {
                $passwdfile = $1;
                last;
            }
        }
        close $ht_fh;
    }
    return $passwdfile;
}

our %API = (
    'setup' => {
        needs_role => 'WebServer',
        allow_demo => 1,
    },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
