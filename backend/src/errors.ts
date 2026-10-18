/** An error safe to show to app users. */
export class ApiError extends Error {
  constructor(
    public readonly status: 400 | 401 | 403 | 404 | 409 | 422 | 429,
    public readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export const badRequest = (message: string, code = 'BAD_REQUEST') => new ApiError(400, code, message);
export const unauthorized = (message = 'Please sign in') => new ApiError(401, 'UNAUTHORIZED', message);
export const forbidden = (message = "You don't have access to this") => new ApiError(403, 'FORBIDDEN', message);
export const notFound = (message = 'Not found') => new ApiError(404, 'NOT_FOUND', message);
export const conflict = (message: string, code = 'CONFLICT') => new ApiError(409, code, message);
export const unprocessable = (message: string, code = 'UNPROCESSABLE') => new ApiError(422, code, message);
