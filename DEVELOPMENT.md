# Developing MCP Client

> TODO: Document the developer instructions here. This is for future me and you and future contributors so we know how to build and test and develop / work on this project.


## Dependencies

1. Make sure you have Crystal toolchain installed.
  - via `brew install crystal` for macOS and Linux (if you are so inclined)
  - or directly [install Crystal](https://crystal-lang.org/install/) from the website
2. Make sure you have `ops` installed, in one of the following ways:
  - as a gem via `gem install ops_team` or
  - as a tool via `brew tap nickthecook/crops && brew install ops`

## Using `ops`

Command               |Description                                                            
----------------------|-----------------------------------------------------------------------
`ops up`              |Gets everything setup, especially dependencies and `ameba` for linting.
`ops specs`           |Run `crystal spec` on the test specs in `spec/`                        
`ops lint`            |Run `ameba` on the source code                                         
`ops test`            |Convenient actions to run tests specs and lint the code                
`ops wipe`            |Clear Crystal build caches                                             
`ops run CRYSTAL_FILE`|Build and run a Crystal app                                            

## Using `crystal` directly

### Dependency check

Run the following to update dependencies and build `ameba` first time or when dependency updates.
```sh
shards check || (shards install && mkdir -p bin && cp lib/ameba/bin/ameba.cr bin && crystal build -o bin/ameba bin/ameba.cr)
```
### Build and test

Command                      |Description                   
-----------------------------|------------------------------
`crystal --order random spec`|Run test specs in random order
`bin/ameba src spec`         |Lint all source code          
`crystal clear_cache`        |Clear Crystal build caches    
`crystal run CRYSTAL_FILE`   |Build and run a Crystal app   

## Contributions

By invitation only for the time being.
