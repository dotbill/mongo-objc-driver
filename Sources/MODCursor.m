//
//  MODCursor.m
//  mongo-objc-driver
//
//  Created by Jérôme Lebel on 11/09/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "MOD_internal.h"

@implementation MODCursor

@synthesize delegate = _delegate, mongoCollection = _mongoCollection, query = _query, fields = _fields, skip = _skip, limit = _limit, sort = _sort;

- (id)initWithMongoCollection:(MODCollection *)mongoCollection
{
    if (self = [self init]) {
        _mongoCollection = [mongoCollection retain];
    }
    return self;
}

- (void)dealloc
{
    if (_cursor) {
        mongo_cursor_destroy(_cursor);
        free(_cursor);
    }
    if (_bsonQuery) {
        bson_destroy(_bsonQuery);
        free(_bsonQuery);
    }
    if (_bsonFields) {
        bson_destroy(_bsonFields);
        free(_bsonFields);
    }
    [_query release];
    [_fields release];
    [_sort release];
    [_mongoCollection release];
    [super dealloc];
}

- (BOOL)_startCursorWithError:(NSError **)error
{
    NSAssert(error != NULL, @"please give a pointer to get the error back");
    NSAssert(_cursor == NULL, @"cursor already created");
    
    *error = nil;
    _cursor = malloc(sizeof(mongo_cursor));
    mongo_cursor_init(_cursor, _mongoCollection.mongo, [_mongoCollection.absoluteCollectionName UTF8String]);
    _bsonQuery = malloc(sizeof(bson));
    bson_init(_bsonQuery);
    
    bson_append_start_object(_bsonQuery, "$query");
    if (_query) {
        [[_mongoCollection.mongoServer class] bsonFromJson:_bsonQuery json:_query error:error];
    }
    bson_append_finish_object(_bsonQuery);
    if (*error == nil) {
        if ([_sort length] > 0) {
            bson_append_start_object(_bsonQuery, "$orderby");
            if (_sort) {
                [[_mongoCollection.mongoServer class] bsonFromJson:_bsonQuery json:_sort error:error];
            }
            bson_append_finish_object(_bsonQuery);
        }
    }
    mongo_cursor_set_query(_cursor, _bsonQuery);
    bson_finish(_bsonQuery);
    if ([_fields count] > 0 && *error == nil) {
        NSUInteger index = 0;
        char indexString[128];
        
        _bsonFields = malloc(sizeof(bson));
        bson_init(_bsonFields);
        for (NSString *field in _fields) {
            snprintf(indexString, sizeof(indexString), "%lu", index);
            bson_append_string(_bsonFields, [field UTF8String], indexString);
        }
        bson_finish(_bsonFields);
        mongo_cursor_set_fields(_cursor, _bsonFields);
    }
    mongo_cursor_set_skip(_cursor, _skip);
    mongo_cursor_set_limit(_cursor, _limit);
    
    return *error == nil;
}

- (NSDictionary *)nextDocumentAsynchronouslyWithError:(NSError **)error;
{
    NSDictionary *result = nil;
    
    NSAssert(error != NULL, @"please give a pointer to get the error back");
    *error = nil;
    if (!_cursor) {
        [self _startCursorWithError:error];
        if (*error == nil) {
            [_mongoCollection.mongoDatabase authenticateSynchronouslyWithError:error];
        }
    }
    if (!*error) {
        if (mongo_cursor_next(_cursor) == MONGO_OK) {
            result = [[_mongoCollection.mongoServer class] objectsFromBson:&(((mongo_cursor *)_cursor)->current)];
        }
    }
    return result;
}

- (void)fetchNextDocumentCallback:(MODQuery *)mongoQuery
{
    if ([_delegate respondsToSelector:@selector(mongoCursor:nextDocumentFetched:withMongoQuery:error:)]) {
        [_delegate mongoCursor:self nextDocumentFetched:[mongoQuery.parameters objectForKey:@"nextdocument"] withMongoQuery:mongoQuery error:mongoQuery.error];
    }
}

- (MODQuery *)fetchNextDocument
{
    MODQuery *query = nil;
    
    query = [_mongoCollection.mongoServer addQueryInQueue:^(MODQuery *mongoQuery) {
        NSDictionary *result;
        NSError *error;
        
        result = [self nextDocumentAsynchronouslyWithError:&error];
        mongoQuery.error = error;
        if (result) {
            [mongoQuery.mutableParameters setObject:result forKey:@"nextdocument"];
        }
        [_mongoCollection.mongoServer mongoQueryDidFinish:mongoQuery withTarget:self callback:@selector(fetchNextDocumentCallback:)];
    }];
    return query;
}

@end