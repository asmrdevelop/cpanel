package Cpanel::Backup::Locate::File;

# cpanel - Cpanel/Backup/Locate/File.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Backup ();
use Cpanel::Tar            ();
use Cpanel::Rand::Get      ();
use Cpanel::SafeDir::RM    ();
use Cpanel::SafeDir::MK    ();

sub new {
    my ($class) = @_;

    my $self = $class->init();

    return bless $self, $class;
}

sub init {
    my ($self) = @_;

    my $rand    = Cpanel::Rand::Get::getranddata(16);
    my $tmp_dir = '/tmp/tempdir' . ".$rand";
    if ( !-d $tmp_dir ) {
        Cpanel::SafeDir::MK::safemkdir( $tmp_dir, '0700' );
    }

    $self = {
        cpbackup    => scalar Cpanel::Config::Backup::load(),
        extract_dir => $tmp_dir,
        stash       => {},
    };
    return $self;
}

sub extract_dir {
    my ($self) = @_;
    return $self->{'extract_dir'};
}

sub backup_dir {
    my ($self) = @_;
    return sprintf "%s/cpbackup", $self->{'cpbackup'}{'BACKUPDIR'};
}

sub is_incremental {
    my ($self) = @_;
    return ( $self->{'cpbackup'}{'BACKUPINC'} =~ /yes/i ) ? 1 : 0;
}

sub is_commpressed {
    my ($self) = @_;
    return ( $self->{'cpbackup'}{'COMPRESSACCTS'} =~ /yes/i ) ? 1 : 0;
}

sub is_ftp {
    my ($self) = @_;
    return ( $self->{'cpbackup'}{'BACKUPTYPE'} =~ /ftp/i ) ? 1 : 0;
}

sub backup_dirs {
    my ($self) = @_;

    opendir( my $dir_h, $self->backup_dir() );
    my @dirs = grep { -d $_ }
      map { $self->backup_dir() . '/' . $_ }
      grep { !/\.\.?/ } readdir($dir_h);
    closedir($dir_h);

    return @dirs;
}

sub get_ext {
    my ($self) = @_;
    return ( $self->is_commpressed() ) ? 'tar.gz' : 'tar';
}

sub get_tar_args {
    my ($self) = @_;
    return ( $self->is_commpressed() ) ? ( '-z', '-p', '-x', '-v', '-f' ) : ( '-p', '-x', '-v', '-f' );
}

sub extract_tar {
    my ( $self, $tar_path, $dir ) = @_;

    my $tarcfg = Cpanel::Tar::load_tarcfg();

    my @args = $self->get_tar_args();

    print "Searching $tar_path\n";
    if ( my $pid = fork() ) {
        my $dotcount = 5;
        while ( waitpid( $pid, 1 ) != -1 ) {
            if ( $dotcount % 5 == 0 ) {
                print ".........\n";
            }
            sleep(1);
            $dotcount++;
        }
    }
    else {
        open( STDOUT, '>', '/dev/null' );
        open( STDERR, '>', '/dev/null' );
        open( STDIN,  '<', '/dev/null' );
        system( $tarcfg->{'bin'}, @args, $tar_path, '-C', $dir );
        exit;
    }
    print "Done\n\n";

}

sub locate {
    my ( $self, $args ) = @_;

    if ( ref $args ne 'HASH' ) {
        warn "Arguments must be be in hash reference.\n";
        return;
    }

    if ( !$args->{'file'} || !$args->{'user'} || !defined $args->{'timestamp'} ) {
        warn "bad arguments.\n";
        return;
    }

    if ( $self->is_ftp() ) {
        warn "Cannot support ftp backups.\n";
        return;
    }

    my @dirs = $self->backup_dirs();

    foreach my $dir (@dirs) {
        next if !-d $dir;

        my $user_path;
        if ( $self->is_incremental() ) {
            $user_path = sprintf "%s/%s", $dir, $args->{'user'};
        }
        else {
            my $ext       = $self->get_ext();
            my $rand      = Cpanel::Rand::Get::getranddata(16);
            my $tar_path  = sprintf "%s/%s.%s", $dir, $args->{'user'}, $ext;
            my $tar_mtime = ( stat($tar_path) )[9];

            next if $tar_mtime > $args->{'timestamp'};

            my $tmp_dir = $self->extract_dir() . '/' . $rand;
            Cpanel::SafeDir::MK::safemkdir( $tmp_dir, '0700' );

            $user_path = sprintf "%s/%s", $tmp_dir, $args->{'user'};

            $self->extract_tar( $tar_path, $tmp_dir );
        }

        my $full_path = $user_path . '/' . $args->{'file'};
        my $mtime     = ( stat($full_path) )[9];

        if ( $mtime < $args->{'timestamp'} ) {
            $self->{'stash'}{$mtime} = $full_path;
        }
    }

    return $self->return_file($args);
}

sub return_file {
    my ( $self, $args ) = @_;
    my @lower_mtime = sort { $a <=> $b } keys %{ $self->{'stash'} };
    my $winner      = pop @lower_mtime;
    return ($winner) ? ( 1, $self->{'stash'}{$winner} ) : ( 0, 'There were no files less old than ' . localtime( $args->{'timestamp'} ) );
}

sub clean_up {
    my ($self) = @_;
    return Cpanel::SafeDir::RM::safermdir( $self->extract_dir() );
}

1;
