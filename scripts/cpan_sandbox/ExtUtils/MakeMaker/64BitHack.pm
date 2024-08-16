## no critic(RequireExplicitPackage)

my $cwd;

eval { require Cwd; $cwd = Cwd::fastcwd(); };

$cwd ||= `pwd`;

chomp($cwd);

if ( $cwd !~ /\/ExtUtils-MakeMaker/ ) {    # case 50362: If we are reinstalling ExtUtils-MakeMaker skip the hack

    eval { require ExtUtils::MakeMaker; };

    if ( !$@ ) {
        my $ExtUtils__MakeMaker__WriteMakefile = \&ExtUtils::MakeMaker::WriteMakefile;
        eval <<'EXTUTILSMAKEMAKERWRITEMAKEFILE_CHANGE_END';
no warnings 'redefine';
sub ExtUtils::MakeMaker::WriteMakefile {
    my %OPTS = @_;
    foreach my $opt ('LIBS','LDFLAGS') {
        if ($OPTS{$opt}) {
            if (ref $OPTS{$opt} eq 'ARRAY') {
                ${$OPTS{$opt}}[0] = "-L/usr/lib64 " . ${$OPTS{$opt}}[0];
            } else {
                $OPTS{$opt} = "-L/usr/lib64 " . $OPTS{$opt};
            }
        }
    }
    return $ExtUtils__MakeMaker__WriteMakefile->(%OPTS);
}
EXTUTILSMAKEMAKERWRITEMAKEFILE_CHANGE_END

    }
}

1;
