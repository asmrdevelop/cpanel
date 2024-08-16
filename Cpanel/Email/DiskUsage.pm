package Cpanel::Email::DiskUsage;

# cpanel - Cpanel/Email/DiskUsage.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Exception               ();
use Cpanel::Fcntl                   ();
use Cpanel::LoadFile                ();
use Cpanel::LoadModule              ();
use Cpanel::SafeFile                ();
use Cpanel::PwCache                 ();
use Cpanel::Email::Maildir          ();
use Cpanel::Email::Maildir::Counter ();
use Cpanel::FileUtils::TouchFile    ();
use Cpanel::SV                      ();

use constant {
    _EDQUOT => 122,
};

my @quota_maildirs = ( 'cur', 'new' );    #tmp is not counted twords quota

our $IGNORE_MAILDIRSIZE_FILES = 0;
our $RENAME                   = 1;
our $VERBOSE                  = 0;
our $DEBUG                    = 0;
our $MIN_UID_WRITE            = 30;       #should be higher then root and mail

our $_CHECK_FOR_ROOT = 1;

*mainacctdiskused = \&recalculate_cpuser_mainacct_email_disk_usage;

sub recalculate_cpuser_mainacct_email_disk_usage {
    my ( $homedir, $maildirsizefile, $rename, $opts_ref ) = @_;
    return recalculate_email_account_disk_usage( $homedir, '_mainaccount', '', $maildirsizefile, $rename, "$homedir/mail", $opts_ref );
}

sub recalculate_email_account_disk_usage {    ## no critic(Subroutines::ProhibitManyArgs)  -- Refactoring this function is a project, not a bug fix
    my ( $homedir, $login, $domain, $maildirsizefile, $rename, $maildir, $opts_ref ) = @_;
    $login =~ s/\0//g;                        #safety check

    if ( !defined $login ) {                  #if its zero its ok
        return wantarray ? ( 0, 0 ) : 0;
    }

    my $create_maildirfolder = ( defined $opts_ref->{'create_maildirfolder'} && $opts_ref->{'create_maildirfolder'} == 0 ) ? 0 : 1;

    $maildir         ||= $homedir . '/mail/' . $domain . '/' . $login;
    $maildirsizefile ||= Cpanel::Email::Maildir::_find_maildirsize_file( $login, $domain, $homedir );

    my ( $diskused, $diskcount ) = _maildirsize_handler( 'rename' => $rename, 'maildir' => $maildir, 'create_maildirfolder' => $create_maildirfolder );

    return wantarray ? ( $diskused, $diskcount ) : $diskused;
}

sub _create_maildirsize_file {
    my ($maildirsizefile) = @_;
    my ( $mdsize_fh, $mdsize_lock );
    my $orig_umask = umask();
    umask(0077);
    print "Creating maildirsize file $maildirsizefile\n" if $VERBOSE;

    # File may have already existed, but with usage at zero. If so, don't wipe out the quota line.
    if ( $mdsize_lock = Cpanel::SafeFile::safesysopen( $mdsize_fh, $maildirsizefile, Cpanel::Fcntl::or_flags(qw( O_RDWR O_CREAT )) ) ) {
        seek( $mdsize_fh, 0, 0 );
        my $quota_line = readline $mdsize_fh;
        truncate $mdsize_fh, tell($mdsize_fh);
        print {$mdsize_fh} "0S,0C\n" unless defined $quota_line;
    }
    umask($orig_umask);
    return ( $mdsize_fh, $mdsize_lock );
}

sub _process_maildir {
    my ( $maildir, $filecounter, $create_maildirfolder ) = @_;
    if ( opendir( my $mail_fh, $maildir ) ) {
        my @dirs;
        while ( my $file = readdir($mail_fh) ) {
            if ( $file =~ /^\.[^\.]+/ && $file ne '.Trash' && $file !~ /@/ && -d $maildir . '/' . $file ) {
                if ( !-e $maildir . '/' . $file . '/maildirfolder' ) {
                    if ($create_maildirfolder) {
                        my ($dir) = "$maildir/$file" =~ m/(.+)/;
                        Cpanel::FileUtils::TouchFile::touchfile( $dir . '/maildirfolder' );
                    }
                    else {
                        next;
                    }
                }
                push @dirs, $file;
            }
        }
        closedir($mail_fh);
        my $dir;

        Cpanel::LoadModule::load_perl_module('Cpanel::SafeFind');
        Cpanel::SafeFind::find(
            { 'wanted' => $filecounter, 'no_chdir' => 1 },

            # only count cur and new (avoiding tmp)
            map { $maildir . '/' . $_ } @quota_maildirs,

            # only count cur and new in the subdirs (avoiding tmp)
            map {
                $dir = $_;
                map { $dir . '/' . $_ } @quota_maildirs
            } @dirs
        );
    }
    return;
}

sub _maildirsize_handler {
    my %OPTS = @_;

    my $rename               = $OPTS{'rename'};
    my $create_maildirfolder = $OPTS{'create_maildirfolder'};
    my $maildir              = $OPTS{'maildir'};

    my $maildirsizefile = "$maildir/maildirsize";

    my ( $has_data, $diskcount, $diskused ) = ( 0, 0, 0 );

    if ( !$rename && $maildirsizefile && !$IGNORE_MAILDIRSIZE_FILES ) {
        print "Calculating diskusage and diskcount from $maildirsizefile\n" if $VERBOSE;
        local $@;
        eval { ( $has_data, $diskused, $diskcount ) = Cpanel::Email::Maildir::Counter::maildirsizecounter($maildirsizefile); };
        if ( $@ && -f $maildirsizefile && -s _ ) {
            warn Cpanel::Exception::get_string($@);
        }
    }

    if ( !-d $maildir ) {
        return ( $diskused, $diskcount );
    }

    if ( !$has_data ) {
        print "Calculating diskusage and diskcount from reading files\n" if $VERBOSE;
        my $mdsize_fh;
        my $mdsize_lock;
        if ( !$IGNORE_MAILDIRSIZE_FILES && $> > $MIN_UID_WRITE ) {
            local $@;
            eval { ( $mdsize_fh, $mdsize_lock ) = _create_maildirsize_file($maildirsizefile); };
            if ( my $err = $@ ) {
                if ( eval { $err->isa('Cpanel::Exception::IO::FileCreateError') } ) {

                    #If we fail to create the maildirsize file because of
                    #a quota error, then we should just stop processing
                    #this user; otherwise, we should warn() and continue
                    #to the next mail account.
                    if ( $err->error() != _EDQUOT() ) {
                        warn "$maildir (UID $>): $!\n";
                    }
                    else {
                        local $@ = $err;
                        die;
                    }
                }
            }
        }
        my ( $count, $filecount ) = ( 0, 0 );

        my $filecounter = sub {
            if ( $File::Find::name =~ /\,S=(\d+)/ ) {    #we can get this from the filename to save a stat

                ( ++$filecount ) && ( $count += $1 );
            }
            elsif ( -f $File::Find::name ) {
                ( ++$filecount ) && ( $count += ( stat(_) )[7] );

                if ($rename) {
                    my $safefile = $File::Find::name;
                    Cpanel::SV::untaint($safefile);
                    my $newfile;
                    if ( $safefile =~ m/:/ ) {
                        my ( $part1, $part2 ) = split( /:/, $safefile, 2 );
                        $newfile = $part1 . ',S=' . ( stat(_) )[7] . ':' . $part2;
                    }
                    else {
                        $newfile = $safefile . ',S=' . ( stat(_) )[7];
                    }
                    rename( $safefile, $newfile );
                }

            }
            elsif ( -d _ && substr( $_, 0, 1 ) eq '.' ) {
                print "Pruning $File::Find::name\n" if $VERBOSE;
                $File::Find::prune = 1              if !-e "$File::Find::name/maildirfolder";
            }
        };

        _process_maildir( $maildir, $filecounter, $create_maildirfolder );

        $diskused  = $count;
        $diskcount = $filecount;
        if ($mdsize_lock) {
            print {$mdsize_fh} "$diskused $filecount\n";
            Cpanel::SafeFile::safeclose( $mdsize_fh, $mdsize_lock );
        }
    }
    return ( $diskused, $diskcount );
}

sub get_disk_used {
    return get_usage_from_file_info( get_email_account_disk_usage_file_info("$_[0]\@$_[1]") );
}

sub get_usage_from_file_info {
    my ($file_ref) = @_;

    # Cpanel::Email::Accounts sets
    #  local $Cpanel::Email::DiskUsage::_CHECK_FOR_ROOT = 0 if $>;
    #  in order to avoid calling geteuid() for every email account
    #  when calculating disk usage.
    die "get_usage_from_file_info may not be called as root" if $_CHECK_FOR_ROOT && !$>;

    if ( $file_ref->{'type'} eq 'dovecot-quota' ) {
        my $value = { split( m{\n}, Cpanel::LoadFile::loadfile( "$file_ref->{'maildir'}/dovecot-quota", { 'skip_exists_check' => 1 } ) ) }->{'priv/quota/storage'};
        return $value if length $value;
    }
    elsif ( $file_ref->{'type'} eq 'diskusage_total' ) {
        return Cpanel::LoadFile::loadfile( "$file_ref->{'maildir'}/diskusage_total", { 'skip_exists_check' => 1 } );
    }

    # Always fallback to maildirsize if available
    if ( ( $file_ref->{'type'} eq 'maildirsize' && $file_ref->{'mtime'} ) || -d "$file_ref->{'maildir'}/cur" ) {
        return ( _maildirsize_handler( 'maildir' => $file_ref->{'maildir'} ) )[0];
    }

    # TODO: it would be nice to return undef here
    # but all calls are expecting unknown to be zero
    return 0;
}

sub get_email_account_disk_usage_file_info {
    my ($email) = @_;

    die "get_email_account_disk_usage_file requires a valid email" if $email =~ tr{\0/}{} || $email !~ tr{@}{} || $email eq '@' || $email =~ tr{/}{};

    Cpanel::SV::untaint($email);
    my $homedir = $Cpanel::homedir || Cpanel::PwCache::gethomedir();

    my ( $local_part, $domain ) = split( m{\@}, $email, 2 );

    if ( $local_part eq '_archive' ) {
        my ( $cache_file_size, $cache_file_mtime ) = ( stat("$homedir/mail/archive/$domain/diskusage_total") )[ 7, 9 ];
        return { 'maildir' => "$homedir/mail/archive/$domain", 'type' => 'diskusage_total', 'size' => $cache_file_size, 'mtime' => $cache_file_mtime };
    }

    my $maildir = get_maildir_for_email_account( $homedir, $email );

    if ( -s "$maildir/dovecot-quota" ) {
        my ( $cache_file_size, $cache_file_mtime ) = ( stat(_) )[ 7, 9 ];
        return { 'maildir' => $maildir, 'type' => 'dovecot-quota', 'size' => $cache_file_size, 'mtime' => $cache_file_mtime };
    }

    # Always fallback to maildirsize
    my ( $cache_file_size, $cache_file_mtime ) = ( stat("$maildir/maildirsize") )[ 7, 9 ];
    return { 'maildir' => $maildir, 'type' => 'maildirsize', 'size' => $cache_file_size, 'mtime' => $cache_file_mtime };
}

sub get_maildir_for_email_account {
    my ( $homedir, $email ) = @_;

    my ( $local_part, $domain ) = split( m{\@}, $email, 2 );
    if ( $local_part eq '_mainaccount' ) {
        return "$homedir/mail";
    }
    return "$homedir/mail/$domain/$local_part";
}

1;
