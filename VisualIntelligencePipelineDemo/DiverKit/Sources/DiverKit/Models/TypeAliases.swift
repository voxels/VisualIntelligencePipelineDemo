//
//  TypeAliases.swift
//  Diver
//
//  Type aliases for API models for cleaner code
//

import Foundation

// MARK: - Core Models

public typealias User = UserRead
public typealias Profile = UserProfile
public typealias Item = ItemRead
public typealias Input = InputRead
public typealias Message = MessageRead
public typealias MessageList = MessageListResponse
public typealias Reference = ReferenceRead
public typealias Media = MediaRead

// MARK: - Auth Models

public typealias BearerToken = BearerResponse
public typealias LoginResponse = BearerResponse
