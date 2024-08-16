package Whostmgr::Remote::Parser::Pkgacct;

# cpanel - Whostmgr/Remote/Parser/Pkgacct.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Exception ();

use base 'Whostmgr::Remote::Parser';

sub init {
    my ($self) = @_;
    $self->{'_last_time_dots_printed'} = time();
    $self->{'_dot_counter'}            = 0;
    $self->{'remote_archive_is_split'} = 0;
    $self->{'remote_file_paths'}       = [];
    $self->{'remote_file_md5sums'}     = [];
    $self->{'remote_file_sizes'}       = [];
    $self->{'remote_username'}         = undef;
    return 1;
}

sub remote_username {
    my ($self) = @_;
    return $self->{'remote_username'};
}

sub remote_file_paths {
    my ($self) = @_;
    return $self->{'remote_file_paths'};
}

sub remote_file_md5sums {
    my ($self) = @_;
    return $self->{'remote_file_md5sums'};
}

sub remote_file_sizes {
    my ($self) = @_;
    return $self->{'remote_file_sizes'};
}

sub remote_archive_is_split {
    my ($self) = @_;
    return $self->{'remote_archive_is_split'};
}

sub _parse_data_line {
    my ( $self, $line ) = @_;

    if ( $line =~ /^\./ || $line =~ /^cpmove-/ ) {
        if ( $self->{'print'} && ( $self->{'_last_time_dots_printed'} + 5 ) < time() ) {
            $self->{'_last_time_dots_printed'} = time();
            print "…" . ( ++$self->{'_dot_counter'} ) . "…\n";
        }
    }
    elsif ( $line =~ /(?:\s+)?mysqladmin: / || $line =~ /(?:\s+)?ERROR: / ) {
        $line =~ s/^\s*//;
        $line =~ s/\s*$//;
        $self->{'raw_error'} = $line;
        die Cpanel::Exception::create( 'RemotePackageAccountFailed', 'The remote “[_1]” command failed because of an error: [_2]', [ 'pkgacct', $self->{'raw_error'} ] );
    }
    elsif ( $line =~ /splitpkgacctfile is: (\S+)/i ) {
        push( @{ $self->{'remote_file_paths'} }, $1 );
        $self->{'remote_archive_is_split'} = 1;
    }
    elsif ( $line =~ /splitmd5sum is: (\S+)/i ) {
        push( @{ $self->{'remote_file_md5sums'} }, $1 );
        $self->{'remote_archive_is_split'} = 1;
    }
    elsif ( $line =~ /homesize is: (\S+)/i ) {
        ## see whm5's calculation of $total_size
        push( @{ $self->{'remote_file_sizes'} }, { 'homesize' => $1 } );
    }
    elsif ( $line =~ /homefiles is: (\S+)/i ) {
        ## see whm5's calculation of $total_size
        push( @{ $self->{'remote_file_sizes'} }, { 'homefiles' => $1 } );
    }
    elsif ( $line =~ /mysqlsize is: (\S+)/i ) {
        push( @{ $self->{'remote_file_sizes'} }, { 'mysqlsize' => $1 } );
    }
    elsif ( $line =~ /size is: (\S+)/i ) {
        ## captures splitsize and size directives from pkgacct
        push( @{ $self->{'remote_file_sizes'} }, { 'size' => $1 } );
    }
    elsif ( $line =~ /pkgacctfile is: (\S+)/i ) {
        push( @{ $self->{'remote_file_paths'} }, $1 );
        $self->{'remote_archive_is_split'} = 0;
    }
    elsif ( $line =~ /realusername is: (\S+)/i ) {
        $self->{'remote_username'} = $1;
    }
    elsif ( !$self->{'remote_username'} && $line =~ /^pkgacct[ \t]+version.*?-[ \t]+user[ \t]+:[ \t]+(\S+)/ ) {
        $self->{'remote_username'} = $1;
    }
    elsif ( $line =~ /md5sum is: (\S+)/i ) {
        push( @{ $self->{'remote_file_md5sums'} }, $1 );
        $self->{'remote_archive_is_split'} = 0;
    }
    elsif ( $line =~ /^\s*$/ || $line =~ /^perl:/ || $line =~ /stdin: is not a tty/ ) {
    }
    else {
        $self->{'result'} .= $line;
        print $line if $self->{'print'};
        $self->{'_dot_counter'} = 0;
    }

    return 1;
}

1;
