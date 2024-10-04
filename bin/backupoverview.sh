# Copyright 2024 Myers Enterprises II
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

printf -v date '%(%Y-%m-%d)T' -1

toolforge-jobs run backupoverview --command "cd /data/project/checkwiki ; mariadb-dump --defaults-file=~/replica.my.cnf --opt --host=tools.db.svc.wikimedia.cloud s51080__checkwiki_p cw_overview >checkwiki${date}.sql" --image mariadb
