#!/usr/bin/env perl

###########################################################################
##
##         FILE: delete-done-articles.pl
##
##        USAGE: ./delete-done-articles.pl -c checkwiki.cfg
##
##  DESCRIPTION: Deletes articles from the database that have been fixed.
##
##       AUTHOR: Stefan Kühn, Bryan White
##      LICENCE: GPLv3
##      VERSION: 08/15/2013
##
###########################################################################

use strict;
use warnings;

use DBI;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);

binmode( STDOUT, ':encoding(UTF-8)' );

##########################################################################
## MAIN PROGRAM
##########################################################################

my @Projects;

#Database configuration
my ( $DbName, $DbServer, $DbUsername, $DbPassword, $config_name, $dbh );

GetOptions(
    'database|d=s' => \$DbName,
    'host|h=s'     => \$DbServer,
    'password=s'   => \$DbPassword,
    'user|u=s'     => \$DbUsername,
    'config|c=s'   => \$config_name
);

if ( defined $config_name ) {
    open( my $file, '<:encoding(UTF-8)', $config_name )
      or die 'Could not open file ' . $config_name . "\n";
    while ( my $line = <$file> ) {
        chomp($line);
        my @words = ( split / /, $line );
        $DbName     = $words[1] if ( $words[0] =~ /--database/ );
        $DbUsername = $words[1] if ( $words[0] =~ /--user/ );
        $DbPassword = $words[1] if ( $words[0] =~ /--password/ );
        $DbServer   = $words[1] if ( $words[0] =~ /--host/ );
    }
    close($file)
      or die 'Could not close file ' . $config_name . "\n";
}
else {
    die("No config file entered, for example: -c checkwiki.cfg\n");
}

#--------------------

open_db();
get_projects();

foreach (@Projects) {
    delete_done_article_from_db($_);
}

close_db();

##########################################################################
## OPEN DATABASE
##########################################################################

sub open_db {

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : q{} ),
        $DbUsername,
        $DbPassword,
        {
            mysql_enable_utf8mb4 => 1
        }
    ) or die( 'Could not connect to database:' . DBI::errstr() . "\n" );

    return ();
}

###########################################################################
## CLOSE DATABASE
###########################################################################

sub close_db {
    $dbh->disconnect();

    return ();
}

###########################################################################
## GET PROJECT NAMES FROM DATABASE (ie enwiki, dewiki)
###########################################################################

sub get_projects {

    my $result = q();
    my $sth = $dbh->prepare('SELECT project FROM cw_overview ORDER BY project;')
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute
      or die "Cannot execute: $sth->errstr\n";

    my ($project_sql);
    $sth->bind_col( 1, \$project_sql );

    while ( $sth->fetchrow_arrayref ) {
        push( @Projects, $project_sql );
    }

    return ();
}

###########################################################################
## DELETE "DONE" ARTICLES FROM DB
###########################################################################

sub delete_done_article_from_db {
    my ($project) = @_;

    my $sth =
      $dbh->prepare('DELETE FROM cw_error WHERE ok = 1 and project = ?;')
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project)
      or die "Cannot execute: $sth->errstr\n";

    return ();
}